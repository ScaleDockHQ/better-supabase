import { describe, expect, it } from "vitest";

import { createTasks } from "../../../src/blocks/tasks/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "w1",
  tenant_id: "o",
  number: 12,
  identifier: "TASK-12",
  title: "Payment API",
  body: "Spec",
  parent_id: "w0",
  team_id: "t1",
  project_id: "p1",
  iteration_id: "i1",
  priority: 2,
  estimate: "3.50",
  progress: 40,
  start_at: "2026-10-20T09:00:00Z",
  end_at: "2026-10-23T09:00:00Z",
  due_at: "2026-10-24T09:00:00Z",
  pipeline_id: "pl1",
  stage_id: "s1",
  stage_entered_at: "2026-10-20T09:00:00Z",
  state: "completed",
  close_reason: "duplicate",
  closed_at: "2026-10-21T09:00:00Z",
  locked: true,
  rank: "V",
  archived_at: null,
  created_by: "u1",
  created_at: "2026-10-14T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  assignees: ["u1", "u2"],
  customer_id: 7,
};

describe("tasks block", () => {
  it("creates with instants as ISO text and reads every field", async () => {
    const t = transport({ create_work_item: () => ROW });

    const item = await createTasks({ transport: t })
      .create(
        "o",
        {
          title: "Payment API",
          startAt: Temporal.Instant.from("2026-10-20T09:00:00Z"),
        },
        ["u1"],
      )
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      attrs: { title: "Payment API", startAt: "2026-10-20T09:00:00Z" },
      assignees: ["u1"],
    });
    expect(item).toMatchObject({
      number: 12n,
      estimate: 3.5,
      state: "completed",
      closeReason: "duplicate",
      locked: true,
      assigneeIds: ["u1", "u2"],
      fields: { customer_id: 7 },
    });
  });

  it("reads a sparse item and sends list filters", async () => {
    const sparse = {
      ...ROW,
      body: null,
      estimate: null,
      progress: null,
      close_reason: null,
      closed_at: null,
      assignees: null,
      customer_id: undefined,
    };

    const t = transport({ list_work_items: () => [sparse] });

    const [item] = await createTasks({ transport: t })
      .list("o", {
        teamId: "t1",
        states: ["started"],
        open: true,
        search: "pay",
        after: "w9",
        limit: 5,
      })
      .orThrow();

    expect(item?.closeReason).toBeUndefined();
    expect(item?.assigneeIds).toEqual([]);
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      filter: { teamId: "t1", states: ["started"], open: true },
      search: "pay",
      after: "w9",
      page_size: 5,
    });
  });

  it("sends changes, assigns, archives, removes and reads the tree", async () => {
    const t = transport({
      update_work_items: () => ({
        accepted: [{ workItemId: "w1", field: "endAt" }],
        rejected: [
          {
            workItemId: "w1",
            field: "dueAt",
            hint: "WORK_ITEM_LOCKED",
            reason: "locked",
          },
        ],
      }),
      set_work_item_assignees: () => 2,
      archive_work_item: () => true,
      delete_work_item: () => true,
      work_item_tree: () => [
        {
          id: "w1",
          parentId: null,
          identifier: "TASK-12",
          title: "x",
          state: "started",
          startAt: null,
          endAt: null,
          dueAt: null,
          locked: false,
          depth: 0,
          progress: 50,
        },
      ],
    });

    const items = createTasks({ transport: t });

    const result = await items
      .update([
        {
          workItemId: "w1",
          field: "endAt",
          value: Temporal.Instant.from("2026-10-23T09:00:00Z"),
        },
      ])
      .orThrow();

    expect(result.rejected[0]?.hint).toBe("WORK_ITEM_LOCKED");
    expect(t.calls[0]?.[1]).toEqual({
      changes: [
        { workItemId: "w1", field: "endAt", value: "2026-10-23T09:00:00Z" },
      ],
    });
    await items
      .update(
        [
          {
            workItemId: "w1",
            field: "window",
            value: {
              startAt: Temporal.Instant.from("2026-10-22T09:00:00Z"),
              endAt: null,
            },
          },
        ],
        { atomic: true },
      )
      .orThrow();
    expect(t.calls[1]?.[1]).toEqual({
      changes: [
        {
          workItemId: "w1",
          field: "window",
          value: { startAt: "2026-10-22T09:00:00Z", endAt: null },
        },
      ],
      atomic: true,
    });
    expect(await items.assign("w1", ["u1", "u2"]).orThrow()).toBe(2);
    expect(await items.archive("w1").orThrow()).toBe(true);
    expect(await items.remove("w1").orThrow()).toBe(true);
    expect((await items.tree("w1").orThrow())[0]).toMatchObject({
      depth: 0,
      progress: 50,
    });
  });

  it("saves projects and iterations with dates as ISO text", async () => {
    const t = transport({
      save_project: () => ({
        id: "p1",
        key: "PAY",
        name: "Payments",
        owner_user_id: null,
        status: "active",
        start_on: "2026-10-01",
        target_on: null,
        progress: 50,
      }),
      save_iteration: () => ({
        id: "i1",
        team_id: null,
        name: "Sprint 1",
        starts_on: "2026-10-19",
        ends_on: "2026-11-01",
      }),
    });

    const items = createTasks({ transport: t });

    const project = await items
      .saveProject("o", {
        key: "PAY",
        name: "Payments",
        startOn: Temporal.PlainDate.from("2026-10-01"),
      })
      .orThrow();

    expect(project).toMatchObject({ key: "PAY", progress: 50 });
    expect(project.startOn?.toString()).toBe("2026-10-01");

    const sprint = await items
      .saveIteration("o", { id: "i1", name: "Sprint 1" })
      .orThrow();

    expect(sprint.endsOn.toString()).toBe("2026-11-01");
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      project: null,
      attrs: { key: "PAY", name: "Payments", startOn: "2026-10-01" },
    });
    expect(t.calls[1]?.[1]).toEqual({
      tenant: "o",
      iteration: "i1",
      attrs: { name: "Sprint 1" },
    });
  });
});

describe("tasks block, sparse rows and options", () => {
  it("reads numbers given as numbers, missing dates and an empty tree node", async () => {
    const sparse = {
      ...ROW,
      number: 3,
      estimate: 2,
      progress: null,
      start_at: null,
      end_at: null,
      due_at: null,
      parent_id: null,
      team_id: null,
      project_id: null,
      iteration_id: null,
      pipeline_id: null,
      stage_id: null,
      stage_entered_at: null,
      priority: null,
      assignees: "u1",
      archived_at: "2026-10-14T09:00:00Z",
    };

    const t = transport({
      create_work_item: () => sparse,
      work_item_tree: () => [
        {
          id: "w1",
          parentId: "w0",
          identifier: "TASK-1",
          title: "x",
          state: "backlog",
          startAt: "2026-10-20T09:00:00Z",
          endAt: "2026-10-21T09:00:00Z",
          dueAt: "2026-10-22T09:00:00Z",
          locked: true,
          depth: null,
          progress: null,
        },
      ],
      save_project: () => ({
        id: "p1",
        key: "PAY",
        name: "Payments",
        owner_user_id: "u1",
        status: "planned",
        start_on: null,
        target_on: "2026-12-31",
        progress: null,
      }),
      save_iteration: () => ({
        id: "i1",
        team_id: "t1",
        name: "Sprint",
        starts_on: null,
        ends_on: null,
      }),
    });

    const items = createTasks({
      transport: t,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: { tree: { after: () => undefined } },
    });

    const item = await items.create("o", { title: "x" }).orThrow();
    expect(item).toMatchObject({
      number: 3n,
      estimate: 2,
      priority: 0,
      assigneeIds: [],
      archived: true,
    });
    expect(item.progress).toBeUndefined();
    expect(t.calls[0]?.[1]).toMatchObject({ assignees: null });
    const [node] = await items.tree("w1").orThrow();
    expect(node).toMatchObject({
      parentId: "w0",
      locked: true,
      depth: 0,
      progress: 0,
    });
    expect(node?.dueAt).toBeDefined();

    const project = await items
      .saveProject("o", { id: "p1", startOn: null })
      .orThrow();

    expect(project).toMatchObject({ ownerId: "u1", status: "planned" });
    expect(project.startOn).toBeUndefined();
    const sprint = await items.saveIteration("o", { name: "Sprint" }).orThrow();
    expect(sprint.teamId).toBe("t1");
    expect(sprint.startsOn.toString()).toBe("1970-01-01");
  });

  it("sends attachments, keeps checklists, a repeat rule and watchers", async () => {
    const rule = {
      rrule: "FREQ=WEEKLY",
      tzid: "Europe/Amsterdam",
      dtstart: "2026-10-24T09:00:00Z",
    };

    const entry = {
      id: "c1",
      workItemId: "w1",
      title: "Draft",
      done: true,
      doneAt: "2026-10-22T09:00:00Z",
      doneBy: "u1",
      rank: "V",
      createdAt: "2026-10-21T09:00:00Z",
    };

    const full = {
      ...ROW,
      checklist: { total: 2, done: 1 },
      recurrence: rule,
      recurs_from: "w0",
    };

    const t = transport({
      create_work_item: () => full,
      get_work_item: (args) => (args["work_item"] === "w1" ? full : null),
      list_work_item_checklist: () => [entry],
      save_work_item_checklist_item: () => ({
        ...entry,
        done: false,
        doneAt: null,
        doneBy: null,
      }),
      delete_work_item_checklist_item: () => true,
      set_work_item_recurrence: (args) =>
        args["rrule"] === null ? null : rule,
      repeat_work_item: () => ({ ...full, id: "w2", recurs_from: "w1" }),
      watch_work_item: () => true,
      list_work_item_watchers: () => [{ userId: "u2", level: "all" }],
    });

    const items = createTasks({ transport: t });

    const item = await items
      .create("o", { title: "Report", attachmentIds: ["a1"] })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: { title: "Report", attachments: ["a1"] },
    });
    expect(item).toMatchObject({
      checklist: { total: 2, done: 1 },
      recurrence: { rrule: "FREQ=WEEKLY", tzid: "Europe/Amsterdam" },
      recursFromId: "w0",
      fields: { customer_id: 7 },
    });
    expect((await items.get("w1").orThrow())?.id).toBe("w1");
    expect(await items.get("w9").orThrow()).toBeUndefined();
    expect(await items.checklist("w1").orThrow()).toEqual([
      {
        ...entry,
        doneAt: Temporal.Instant.from(entry.doneAt),
        createdAt: Temporal.Instant.from(entry.createdAt),
      },
    ]);

    const saved = await items
      .saveChecklistItem("w1", { done: false }, "c1")
      .orThrow();

    expect(saved.doneAt).toBeUndefined();
    expect(t.calls.at(-1)?.[1]).toEqual({
      work_item: "w1",
      checklist_item: "c1",
      attrs: { done: false },
    });
    await items.saveChecklistItem("w1", { title: "Send" }).orThrow();
    expect(t.calls.at(-1)?.[1]).toMatchObject({ checklist_item: null });
    expect(await items.removeChecklistItem("c1").orThrow()).toBe(true);

    expect(
      (await items.setRecurrence("w1", { rrule: "FREQ=WEEKLY" }).orThrow())
        ?.dtstart,
    ).toEqual(Temporal.Instant.from(rule.dtstart));
    expect(t.calls.at(-1)?.[1]).toEqual({
      work_item: "w1",
      rrule: "FREQ=WEEKLY",
      tzid: "UTC",
    });
    expect(await items.setRecurrence("w1", null).orThrow()).toBeUndefined();

    const next = Temporal.Instant.from("2026-10-31T09:00:00Z");
    expect((await items.repeat("w1", next).orThrow()).recursFromId).toBe("w1");
    expect(t.calls.at(-1)?.[1]).toEqual({
      work_item: "w1",
      due_at: "2026-10-31T09:00:00Z",
    });
    expect(await items.watch("w1", "all").orThrow()).toBe(true);
    expect(await items.watchers("w1").orThrow()).toEqual([
      { userId: "u2", level: "all" },
    ]);
  });
});
