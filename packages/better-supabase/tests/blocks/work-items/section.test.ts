import { describe, expect, it, vi } from "vitest";

import type {
  ChecklistItem,
  WorkItems,
} from "../../../src/blocks/work-items/index.ts";

import {
  workItemChecklistOptimistic,
  workItemChecklistSection,
  workItemsBlock,
} from "../../../src/blocks/work-items/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const item = (id: string, rank: string, done = false): ChecklistItem => ({
  id,
  workItemId: "w1",
  title: id,
  done,
  rank,
  createdAt: Temporal.Instant.from("2026-10-22T08:00:00Z"),
});

describe("workItemChecklistSection", () => {
  it("loads the work item's checklist and goes stale on its updates", async () => {
    const checklist = vi.fn((_id: string) => AsyncResult.ok([item("a", "a0")]));

    // SAFETY: the section calls only `checklist`.
    const client = { checklist } as unknown as WorkItems;

    const loaded = await workItemChecklistSection.load(
      client,
      { type: "task", id: "w1" },
      undefined,
    );

    expect(loaded.ok && loaded.data.map((row) => row.id)).toEqual(["a"]);
    expect(checklist).toHaveBeenCalledWith("w1");
    expect(workItemChecklistSection.events).toEqual(["work_item.updated"]);
    expect(workItemsBlock.sections.checklist).toBe(workItemChecklistSection);
  });

  it("applies a save in rank order and a remove", () => {
    const state = [item("a", "a0"), item("c", "a2")];

    expect(
      workItemChecklistOptimistic(state, {
        type: "save",
        item: item("b", "a1"),
      }).map((row) => row.id),
    ).toEqual(["a", "b", "c"]);
    expect(
      workItemChecklistOptimistic(state, {
        type: "save",
        item: item("a", "a3", true),
      }).map((row) => [row.id, row.done]),
    ).toEqual([
      ["c", false],
      ["a", true],
    ]);
    expect(
      workItemChecklistOptimistic([item("x", "a0"), item("y", "a0")], {
        type: "save",
        item: item("z", "a0"),
      }).map((row) => row.id),
    ).toEqual(["x", "y", "z"]);
    expect(
      workItemChecklistOptimistic(state, { type: "remove", id: "a" }).map(
        (row) => row.id,
      ),
    ).toEqual(["c"]);
    expect(
      workItemChecklistOptimistic(
        state,
        // SAFETY: an action outside the union reaches the exhaustive default.
        { type: "unknown" } as unknown as Parameters<
          typeof workItemChecklistOptimistic
        >[1],
      ),
    ).toEqual({ type: "unknown" });
  });
});
