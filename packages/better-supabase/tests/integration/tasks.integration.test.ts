import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createRank } from "../../src/blocks/rank/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
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
  "tasks",
];

// The shared stack's work_items table references `work_projects` (the Next.js
// example renames it), and `create table if not exists` keeps that table.
const layout = (
  maxAssignees = 0,
  options: Readonly<Record<string, unknown>> = {},
): BlockSqlLayout => ({
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: {
    tasks: {
      tables: { projects: "work_projects" },
      options: { maxAssignees, ...options },
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
      const items = createTasks({ transport });
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

  it("names the item and links to it in the assignment notification, or leaves it to the app", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const dev = await s.user("dev");
      await s.install(MODULES, layout(0, { actionPath: "/tasks/{id}" }));
      const org = await s.organization(owner, { member: dev });
      const items = createTasks({ transport: sqlTransport(s.sql) });

      await s.as(owner);
      const item = await items.create(org, { title: "Ship it" }).orThrow();
      await items.assign(item.id, [dev.id]).orThrow();

      expect(
        await s.rows(
          "select subject_label, action_path from better_supabase.notification_events where type = 'work_item.assigned'",
        ),
      ).toEqual([
        { subject_label: "Ship it", action_path: `/tasks/${item.id}` },
      ]);

      await s.install(["tasks"], layout(0, { notify: false }));
      const quiet = await items.create(org, { title: "Quiet" }).orThrow();
      await items.assign(quiet.id, [dev.id]).orThrow();

      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.notification_events where type = 'work_item.assigned')",
        ),
      ).toBe(1);
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
      const items = createTasks({ transport: sqlTransport(s.sql) });

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

  it("moves a window in one write and keeps all or none of an atomic batch", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES, layout());
      const org = await s.organization(owner);
      const items = createTasks({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const item = await items
        .create(org, {
          title: "Launch",
          startAt: Temporal.Instant.from("2026-11-02T09:00:00Z"),
          endAt: Temporal.Instant.from("2026-11-03T17:00:00Z"),
        })
        .orThrow();

      const later = {
        startAt: Temporal.Instant.from("2026-11-10T09:00:00Z"),
        endAt: Temporal.Instant.from("2026-11-11T17:00:00Z"),
      };

      const split = await items
        .update([
          { workItemId: item.id, field: "startAt", value: later.startAt },
          { workItemId: item.id, field: "endAt", value: later.endAt },
        ])
        .orThrow();

      expect(split.rejected.map((change) => change.field)).toEqual(["startAt"]);

      const moved = await items
        .update([{ workItemId: item.id, field: "window", value: later }])
        .orThrow();

      expect(moved).toEqual({
        accepted: [{ workItemId: item.id, field: "window" }],
        rejected: [],
      });

      const failed = await items.update(
        [
          { workItemId: item.id, field: "title", value: "Launch v2" },
          { workItemId: item.id, field: "priority", value: "high" },
        ],
        { atomic: true },
      );

      expect(failed.ok).toBe(false);

      const kept = await items.get(item.id).orThrow();

      expect(kept?.title).toBe("Launch");
      expect(kept?.startAt?.toString()).toBe(later.startAt.toString());
      expect(kept?.endAt?.toString()).toBe(later.endAt.toString());
    } finally {
      await s.close();
    }
  });

  it("keeps checklists, watchers, attachments and a repeat rule", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const dev = await s.user("dev");
      const other = await s.user("other");
      await s.install([...MODULES, "attachments", "reminders"], layout());
      const org = await s.organization(owner, { member: dev, member2: other });
      const items = createTasks({ transport: sqlTransport(s.sql) });

      await s.service();

      const file = async (user: string): Promise<string> => {
        const { rows } = await s.client.query<{ id: string }>(
          "insert into better_supabase.attachments (organization_id, bucket, name, mime_type, size, status, uploaded_by) values ($1, 'attachments', 'spec.pdf', 'application/pdf', 10, 'clean', $2) returning id::text",
          [org, user],
        );

        return rows[0]?.id ?? "";
      };

      const mine = await file(dev.id);
      const theirs = await file(other.id);
      const later = await file(dev.id);

      await s.as(dev);

      const due = Temporal.Instant.from("2026-11-02T09:00:00Z");

      expect(
        hint(
          await items.create(org, { title: "Report", attachmentIds: [theirs] }),
        ),
      ).toBe("WORK_ITEM_ATTACHMENTS_INVALID");

      const item = await items
        .create(
          org,
          {
            title: "Weekly report",
            dueAt: due,
            startAt: due.subtract({ hours: 2 }),
            attachmentIds: [mine],
          },
          [dev.id],
        )
        .orThrow();

      expect(item.checklist).toEqual({ total: 0, done: 0 });

      const subjectOf = (id: string) =>
        s.value<string | null>(
          "(select subject_type || ':' || subject_id from better_supabase.attachments where id = $1)",
          [id],
        );

      expect(await subjectOf(mine)).toBe(`work_item:${item.id}`);

      const linked = await items
        .update([
          { workItemId: item.id, field: "attachments", value: [later] },
          { workItemId: item.id, field: "attachments", value: [theirs] },
        ])
        .orThrow();

      expect(linked.accepted).toHaveLength(1);
      expect(linked.rejected.map((change) => change.hint)).toEqual([
        "WORK_ITEM_ATTACHMENTS_INVALID",
      ]);
      expect(await subjectOf(later)).toBe(`work_item:${item.id}`);

      const draft = await items
        .saveChecklistItem(item.id, { title: "Draft" })
        .orThrow();

      const send = await items
        .saveChecklistItem(item.id, { title: "Send", done: true })
        .orThrow();

      expect(send.rank > draft.rank).toBe(true);
      expect(send).toMatchObject({ done: true, doneBy: dev.id });
      await items
        .saveChecklistItem(item.id, { done: true }, draft.id)
        .orThrow();
      await items
        .saveChecklistItem(item.id, { done: false }, send.id)
        .orThrow();
      expect(hint(await items.saveChecklistItem(item.id, { title: "" }))).toBe(
        "WORK_ITEM_CHECKLIST_ITEM_INVALID",
      );

      await s.asRole(dev);

      const checklist = await items.checklist(item.id).orThrow();
      expect(checklist.map((entry) => [entry.title, entry.done])).toEqual([
        ["Draft", true],
        ["Send", false],
      ]);
      expect(checklist[1]?.doneAt).toBeUndefined();
      expect((await items.get(item.id).orThrow())?.checklist).toEqual({
        total: 2,
        done: 1,
      });

      await s.as(dev);
      expect(
        hint(await items.setRecurrence(item.id, { rrule: "every monday" })),
      ).toBe("WORK_ITEM_RECURRENCE_INVALID");

      const rule = await items
        .setRecurrence(item.id, {
          rrule: "RRULE:FREQ=WEEKLY;BYDAY=MO",
          tzid: "Europe/Amsterdam",
        })
        .orThrow();

      expect(rule).toMatchObject({
        rrule: "FREQ=WEEKLY;BYDAY=MO",
        tzid: "Europe/Amsterdam",
      });
      expect(rule?.dtstart.equals(due)).toBe(true);

      await s.as(other);
      expect(await items.watch(item.id, "all").orThrow()).toBe(true);
      expect(await items.watchers(item.id).orThrow()).toEqual(
        expect.arrayContaining([
          { userId: dev.id, level: "participating" },
          { userId: other.id, level: "all" },
        ]),
      );
      expect(await items.watch(item.id, "ignore").orThrow()).toBe(true);
      expect(
        (await items.watchers(item.id).orThrow()).map((w) => w.userId),
      ).toEqual([dev.id]);
      await s.asRole(other);
      expect((await items.repeat(item.id, due)).ok).toBe(false);

      await s.service();

      const next = due.add({ hours: 24 * 7 });
      const copy = await items.repeat(item.id, next).orThrow();

      expect(copy).toMatchObject({
        title: "Weekly report",
        recursFromId: item.id,
        assigneeIds: [dev.id],
        checklist: { total: 2, done: 0 },
      });
      expect(copy.dueAt?.equals(next)).toBe(true);
      expect(copy.startAt?.equals(next.subtract({ hours: 2 }))).toBe(true);
      expect(copy.recurrence?.rrule).toBe("FREQ=WEEKLY;BYDAY=MO");
      expect((await items.get(item.id).orThrow())?.recurrence).toBeUndefined();
      expect((await items.repeat(item.id, next).orThrow()).id).toBe(copy.id);

      await s.as(dev);
      expect(await items.removeChecklistItem(draft.id).orThrow()).toBe(true);
      expect(await items.removeChecklistItem(draft.id).orThrow()).toBe(false);
      expect(
        (await items.setRecurrence(copy.id, null).orThrow()) ?? null,
      ).toBeNull();
    } finally {
      await s.close();
    }
  });
});
