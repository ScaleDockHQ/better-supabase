import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createRank } from "../../src/blocks/rank/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { createWorkItems } from "../../src/blocks/work-items/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "rank",
  "relations",
  "pipelines",
  "work-items",
];

// The shared stack's work_items table references `work_projects` (the Next.js
// example renames it), and `create table if not exists` keeps that table.
const layout = (maxAssignees = 0): ModuleLayout => ({
  subjects: withBlockSubjects({}, ["work-items"], {}),
  modules: {
    "work-items": {
      tables: { projects: "work_projects" },
      options: { maxAssignees },
    },
  },
});

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("work items", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs items through their team's pipeline with parents, assignees and a tree", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const dev = await s.user("dev");
      const pm = await s.user("pm");
      await s.install(MODULES, layout());
      const org = await s.organization(owner, { member: dev, member2: pm });
      const transport = sqlTransport(s.sql);
      const items = createWorkItems({ transport });
      const pipelines = createPipelines({ transport });
      const team = crypto.randomUUID();

      await s.as(pm);

      const epic = await items
        .create(org, { title: "Checkout v2", teamId: team, priority: 2 })
        .orThrow();

      expect(epic).toMatchObject({
        identifier: "TASK-1",
        state: "triage",
        priority: 2,
        teamId: team,
      });
      const [pipeline] = await pipelines.list(org, "work_item").orThrow();
      expect(pipeline?.scopeId).toBe(team);
      expect(pipeline?.stages.map((stage) => stage.key)).toEqual([
        "triage",
        "backlog",
        "todo",
        "in_progress",
        "in_review",
        "done",
        "canceled",
      ]);

      const stage = (key: string): string =>
        pipeline?.stages.find((item) => item.key === key)?.id ?? "";

      const start = Temporal.Instant.from("2026-10-20T09:00:00Z");

      const api = await items
        .create(
          org,
          {
            title: "Payment API",
            parentId: epic.id,
            teamId: team,
            startAt: start,
            endAt: start.add({ hours: 72 }),
          },
          [dev.id, pm.id],
        )
        .orThrow();

      const ui = await items
        .create(org, { title: "Payment UI", parentId: epic.id, teamId: team }, [
          dev.id,
        ])
        .orThrow();

      expect(api.assigneeIds.toSorted()).toEqual([dev.id, pm.id].toSorted());

      const result = await items
        .update([
          { workItemId: api.id, field: "stageId", value: stage("done") },
          { workItemId: ui.id, field: "stageId", value: stage("canceled") },
          { workItemId: epic.id, field: "parentId", value: api.id },
          { workItemId: api.id, field: "priority", value: 9 },
        ])
        .orThrow();

      expect(result.accepted.map((item) => item.field)).toEqual([
        "stageId",
        "stageId",
      ]);
      expect(result.rejected.map((item) => item.hint)).toEqual([
        "WORK_ITEM_PARENT_CYCLE",
        undefined,
      ]);

      const tree = await items.tree(epic.id).orThrow();
      expect(
        tree
          .map((node) => [node.title, node.depth, node.progress])
          .toSorted((a, b) => String(a[0]).localeCompare(String(b[0]))),
      ).toEqual([
        ["Checkout v2", 0, 100],
        ["Payment API", 1, 100],
        ["Payment UI", 1, 0],
      ]);

      const done = (
        await items.list(org, { states: ["completed"] }).orThrow()
      )[0];

      expect(done).toMatchObject({
        id: api.id,
        state: "completed",
        closeReason: "completed",
      });
      expect(done?.closedAt).toBeDefined();

      const canceled = (
        await items.list(org, { states: ["canceled"] }).orThrow()
      )[0];

      expect(canceled?.closeReason).toBe("not_planned");
      await items
        .update([
          { workItemId: api.id, field: "stageId", value: stage("in_progress") },
        ])
        .orThrow();

      const reopened = (
        await items.list(org, { search: "Payment API" }).orThrow()
      )[0];

      expect(reopened).toMatchObject({ state: "started" });
      expect(reopened?.closedAt).toBeUndefined();
      expect(
        (
          await items.list(org, { assigneeId: pm.id, open: true }).orThrow()
        ).map((item) => item.id),
      ).toEqual([api.id]);

      await s.as(owner);

      const link = await createRelations({ transport, tenant: org })
        .link(
          { type: "work_item", id: api.id },
          { type: "work_item", id: ui.id },
          { kind: "blocks" },
        )
        .orThrow();

      expect(link.created).toBe(true);
      await s.as(pm);

      const assigned = await s.value<number>(
        "(select count(*)::int from better_supabase.notification_events e join better_supabase.notification_recipients r on r.event_id = e.id where e.type = 'work_item.assigned' and r.user_id = $1)",
        [dev.id],
      );

      expect(assigned).toBe(2);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.notification_subscriptions where subject_type = 'work_item' and user_id = $1)",
          [dev.id],
        ),
      ).toBe(2);

      const second = await items
        .create(org, { title: "Docs", teamId: team })
        .orThrow();

      await createRank({ transport })
        .move("work_item", second.id, { group: stage("todo") })
        .orThrow();
      expect(
        (await items.list(org, { search: "Docs" }).orThrow())[0],
      ).toMatchObject({ state: "unstarted", stageId: stage("todo") });
    } finally {
      await s.close();
    }
  });

  it("limits assignees, locks dates and keeps projects and iterations", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const dev = await s.user("dev");
      const other = await s.user("other");
      await s.install(MODULES, layout(1));
      const org = await s.organization(owner, { member: dev, member2: other });
      const items = createWorkItems({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const project = await items
        .saveProject(org, {
          key: "pay",
          name: "Payments",
          status: "active",
          startOn: Temporal.PlainDate.from("2026-10-01"),
        })
        .orThrow();

      expect(project).toMatchObject({ key: "PAY", status: "active" });

      const sprint = await items
        .saveIteration(org, {
          name: "Sprint 1",
          startsOn: Temporal.PlainDate.from("2026-10-19"),
          endsOn: Temporal.PlainDate.from("2026-11-01"),
        })
        .orThrow();

      expect(
        hint(
          await items.saveIteration(org, {
            name: "Bad",
            startsOn: Temporal.PlainDate.from("2026-11-01"),
            endsOn: Temporal.PlainDate.from("2026-10-01"),
          }),
        ),
      ).toBe("WORK_ITEM_ITERATION_INVALID");

      await s.as(dev);
      expect(hint(await items.saveProject(org, { key: "X", name: "X" }))).toBe(
        "WORK_ITEM_FORBIDDEN",
      );

      const item = await items
        .create(
          org,
          {
            title: "Ledger",
            projectId: project.id,
            iterationId: sprint.id,
            dueAt: Temporal.Instant.from("2026-10-30T00:00:00Z"),
          },
          [dev.id],
        )
        .orThrow();

      expect(hint(await items.assign(item.id, [dev.id, other.id]))).toBe(
        "WORK_ITEM_ASSIGNEES_LIMIT",
      );
      await items
        .update([
          {
            workItemId: item.id,
            field: "stageId",
            value: await s.value<string>(
              "(select id::text from better_supabase.pipeline_stages where key = 'done' and pipeline_id = $1)",
              [item.pipelineId],
            ),
          },
        ])
        .orThrow();
      await s.as(owner);
      expect(
        (await items.saveProject(org, { id: project.id }).orThrow()).progress,
      ).toBe(100);

      await s.service();
      await s.client.query(
        "update better_supabase.work_items set locked = true where id = $1",
        [item.id],
      );
      await s.as(dev);

      const locked = await items
        .update([
          { workItemId: item.id, field: "dueAt", value: null },
          { workItemId: item.id, field: "title", value: "Ledger v2" },
        ])
        .orThrow();

      expect(locked.rejected.map((change) => change.hint)).toEqual([
        "WORK_ITEM_LOCKED",
      ]);
      expect(hint(await items.create(org, { title: "" }))).toBe(
        "WORK_ITEM_TITLE_REQUIRED",
      );
      await s.as(other);
      expect(await items.remove(item.id).orThrow()).toBe(false);
      await s.as(dev);
      expect(await items.remove(item.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });
});
