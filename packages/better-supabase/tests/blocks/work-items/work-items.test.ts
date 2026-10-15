import { describe, expect, it } from "vitest";

import {
  createWorkItems,
  workItemsSubjects,
} from "../../../src/blocks/work-items/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
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

describe("work-items block", () => {
  it("creates with instants as ISO text and reads every field", async () => {
    const t = transport({ create_work_item: () => ROW });
    const item = await createWorkItems({ transport: t })
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
    const [item] = await createWorkItems({ transport: t })
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
    const items = createWorkItems({ transport: t });
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
    const items = createWorkItems({ transport: t });
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

  it("registers work items as a ranked subject", () => {
    expect(workItemsSubjects({ url: "/t/{id}" }).work_item).toMatchObject({
      table: "better_supabase.work_items",
      rank: { group: "stage_id" },
      url: "/t/{id}",
    });
    expect(workItemsSubjects().work_item.url).toBeUndefined();
  });
});
