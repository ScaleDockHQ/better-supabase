import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createIncidents } from "../../src/blocks/incidents/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "incidents"];

const WITH_TASKS = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "rank",
  "relations",
  "pipelines",
  "tasks",
  "incidents",
];

// The Next.js example names its projects table `work_projects`; this suite does
// too.
const TASKS_LAYOUT: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: { tasks: { tables: { projects: "work_projects" } } },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("incidents", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs an incident to a postmortem and shows only its public parts on the status page", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const responder = await s.user("responder");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: responder });
      const other = await s.organization(outsider);
      const slug = `status-${crypto.randomUUID().slice(0, 8)}`;
      const incidents = createIncidents({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const api = await incidents
        .saveComponent(org, { name: "API", group: "Platform" })
        .orThrow();

      const db = await incidents
        .saveComponent(org, { name: "Primary database", public: false })
        .orThrow();

      expect(api).toMatchObject({ public: true, status: "operational" });
      await incidents
        .saveStatusPage(org, { slug, title: "Acme status", published: true })
        .orThrow();

      await s.as(outsider);
      expect(
        await incidents
          .saveStatusPage(other, { slug, title: "Copycat" })
          .then(hint),
      ).toBe("STATUS_PAGE_SLUG_TAKEN");

      await s.as(responder);

      const incident = await incidents
        .open(org, {
          title: "Elevated API errors",
          severity: "sev2",
          public: true,
          message: "We are looking into elevated error rates.",
          impacts: [
            { componentId: api.id, impact: "partial_outage" },
            { componentId: db.id, impact: "degraded" },
          ],
        })
        .orThrow();

      expect(incident).toMatchObject({
        status: "investigating",
        severity: "sev2",
        createdBy: responder.id,
      });
      expect(
        (await incidents.components(org).orThrow()).map((item) => item.status),
      ).toEqual(["partial_outage", "degraded"]);

      const secret = await incidents
        .open(org, { title: "Leaked credentials", severity: "sev1" })
        .orThrow();

      expect(secret.public).toBe(false);

      await incidents
        .postUpdate(incident.id, {
          status: "identified",
          body: "A replica fell behind; failing over.",
          public: false,
        })
        .orThrow();
      await incidents
        .postUpdate(incident.id, {
          status: "monitoring",
          body: "A fix is in place and we are monitoring.",
        })
        .orThrow();
      expect(await incidents.publishPostmortem(incident.id).then(hint)).toBe(
        "INCIDENTS_FORBIDDEN",
      );
      await incidents
        .savePostmortem(incident.id, { summary: "Early notes" })
        .orThrow();
      await s.as(owner);
      expect(await incidents.publishPostmortem(incident.id).then(hint)).toBe(
        "INCIDENT_NOT_RESOLVED",
      );
      await s.as(responder);

      await incidents
        .postUpdate(incident.id, { status: "resolved", body: "Resolved." })
        .orThrow();
      const resolved = await incidents.get(incident.id).orThrow();
      expect(resolved?.resolvedAt).toBeDefined();
      expect(resolved?.updates.map((update) => update.status)).toEqual([
        "investigating",
        "identified",
        "monitoring",
        "resolved",
      ]);
      expect(
        (await incidents.components(org).orThrow()).map((item) => item.status),
      ).toEqual(["operational", "operational"]);

      await incidents
        .savePostmortem(incident.id, {
          summary: "Replica lag caused failed writes.",
          rootCause: "A replica on an undersized disk",
          // oxlint-disable-next-line typescript/no-deprecated -- the install without tasks still writes the deprecated list.
          actionItems: [{ title: "Alert on replica lag" }],
        })
        .orThrow();
      await s.as(owner);
      expect(
        (await incidents.publishPostmortem(incident.id).orThrow()).status,
      ).toBe("published");
      await incidents
        .postUpdate(secret.id, { status: "resolved", body: "Keys rotated." })
        .orThrow();
      expect(await incidents.publishPostmortem(secret.id).then(hint)).toBe(
        "INCIDENT_POSTMORTEM_NOT_FOUND",
      );

      await s.asRole(outsider);
      expect(await incidents.list(org).orThrow()).toEqual([]);
      expect(await incidents.get(secret.id).orThrow()).toBeUndefined();

      await s.asRole("anon");
      const page = await incidents.publicStatusPage(slug, 7).orThrow();
      expect(page).toMatchObject({
        slug,
        title: "Acme status",
        days: 7,
        status: "operational",
      });
      expect(page?.components.map((item) => item.name)).toEqual(["API"]);
      expect(page?.components[0]?.uptime).toHaveLength(7);
      expect(page?.components[0]?.uptime.at(-1)?.status).toBe("partial_outage");
      expect(page?.incidents.map((item) => item.title)).toEqual([
        "Elevated API errors",
      ]);
      expect(page?.incidents[0]?.components).toEqual([
        { id: api.id, name: "API", impact: "partial_outage" },
      ]);
      expect(
        page?.incidents[0]?.updates.map((update) => update.status),
      ).toEqual(["resolved", "monitoring", "investigating"]);
      expect(page?.incidents[0]?.postmortem?.summary).toBe(
        "Replica lag caused failed writes.",
      );

      const text = JSON.stringify(page);

      for (const hidden of [
        "Leaked credentials",
        "replica fell behind",
        "Primary database",
        "undersized disk",
        org,
        responder.id,
      ]) {
        expect(text).not.toContain(hidden);
      }

      expect(
        await s.hint("select count(*) from better_supabase.incidents"),
      ).toMatch(/GRANT SELECT ON better_supabase.incidents TO anon/);
      expect(
        await incidents.publicStatusPage("no-such-page").orThrow(),
      ).toBeUndefined();

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select distinct type collate \"C\" as type from better_supabase.outbox_events where type like any (array['incident.%', 'incident_postmortem.%', 'status_component.%']) order by type",
      );

      expect(events.map((row) => row.type)).toEqual([
        "incident.opened",
        "incident.resolved",
        "incident.updated",
        "incident_postmortem.published",
        "status_component.changed",
      ]);
    } finally {
      await s.close();
    }
  });

  it("keeps postmortem action items as tasks", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const responder = await s.user("responder");
      const outsider = await s.user("outsider");
      await s.install(WITH_TASKS, TASKS_LAYOUT);
      const org = await s.organization(owner, { member: responder });
      const incidents = createIncidents({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const incident = await incidents
        .open(org, { title: "Queue backlog", severity: "sev3" })
        .orThrow();

      const postmortem = await incidents
        .savePostmortem(incident.id, { summary: "Workers stalled" })
        .orThrow();

      expect(
        await incidents
          // oxlint-disable-next-line typescript/no-deprecated -- checks that the deprecated key is refused with tasks.
          .savePostmortem(incident.id, { actionItems: [{ title: "Old" }] })
          .then(hint),
      ).toBe("INCIDENTS_INVALID");

      const due = Temporal.Instant.from("2026-11-01T09:00:00Z");

      const action = await incidents
        .addPostmortemAction(postmortem.id, {
          title: "Alert on queue depth",
          assigneeId: responder.id,
          dueAt: due,
        })
        .orThrow();

      expect(action).toMatchObject({
        postmortemId: postmortem.id,
        title: "Alert on queue depth",
      });
      expect(action.dueAt?.equals(due)).toBe(true);
      await incidents
        .addPostmortemAction(postmortem.id, { title: "Runbook" })
        .orThrow();

      await s.service();
      expect(
        await s.rows<{ title: string; tenant_id: string }>(
          "select title, tenant_id from better_supabase.tasks where id = $1",
          [action.taskId],
        ),
      ).toEqual([{ title: "Alert on queue depth", tenant_id: org }]);

      await s.asRole(responder);
      const detail = await incidents.get(incident.id).orThrow();
      expect(detail?.postmortem?.actions.map((item) => item.title)).toEqual([
        "Alert on queue depth",
        "Runbook",
      ]);
      // oxlint-disable-next-line typescript/no-deprecated -- checks that the deprecated list stays empty with tasks.
      expect(detail?.postmortem?.actionItems).toEqual([]);

      await s.asRole(outsider);
      expect(await incidents.removePostmortemAction(action.id).then(hint)).toBe(
        "INCIDENTS_FORBIDDEN",
      );
      expect(
        await incidents
          .addPostmortemAction(postmortem.id, { title: "Sneaky" })
          .then(hint),
      ).toBe("INCIDENTS_FORBIDDEN");

      await s.asRole(owner);
      const after = await incidents.removePostmortemAction(action.id).orThrow();
      expect(after.actions.map((item) => item.title)).toEqual(["Runbook"]);
      expect(await incidents.removePostmortemAction(action.id).then(hint)).toBe(
        "INCIDENT_POSTMORTEM_ACTION_NOT_FOUND",
      );

      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.tasks where id = $1)",
          [action.taskId],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("copies action items written before the tasks block into tasks without losing one", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const responder = await s.user("responder");
      await s.install(WITH_TASKS, TASKS_LAYOUT);
      const org = await s.organization(owner, { member: responder });
      const incidents = createIncidents({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const incident = await incidents
        .open(org, { title: "Disk full", severity: "sev2" })
        .orThrow();

      const postmortem = await incidents
        .savePostmortem(incident.id, { summary: "Logs filled the disk" })
        .orThrow();

      const items = [
        {
          title: "Rotate logs",
          assigneeId: responder.id,
          dueAt: "2026-11-02T09:00:00Z",
        },
        "Add a disk alert",
        { text: "Review retention", assigneeId: "not-a-uuid", dueAt: "soon" },
        { owner: "ops" },
      ];

      await s.service();
      await s.rows(
        "update better_supabase.incident_postmortems set action_items = $1::jsonb where id = $2",
        [JSON.stringify(items), postmortem.id],
      );

      const data = renderBlocks(WITH_TASKS, TASKS_LAYOUT).find(
        (file) => file.module === "incidents" && file.kind === "data",
      );

      expect(data).toBeDefined();
      await s.rows(data?.contents ?? "");
      // A second run adds nothing.
      await s.rows(data?.contents ?? "");

      await s.asRole(owner);
      const detail = await incidents.get(incident.id).orThrow();
      const actions = detail?.postmortem?.actions ?? [];

      expect(actions.map((item) => item.title)).toEqual([
        "Rotate logs",
        "Add a disk alert",
        "Review retention",
        "Action item 4",
      ]);
      expect(actions[0]?.dueAt?.toString()).toBe("2026-11-02T09:00:00Z");

      await s.service();
      // The column stays readable.
      expect(
        await s.value<number>(
          "(select jsonb_array_length(action_items) from better_supabase.incident_postmortems where id = $1)",
          [postmortem.id],
        ),
      ).toBe(items.length);
    } finally {
      await s.close();
    }
  });
});
