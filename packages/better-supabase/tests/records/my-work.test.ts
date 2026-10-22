import { describe, expect, it, vi } from "vitest";

import type { MyWorkItem } from "../../src/records/index.ts";

import { loadMyWork } from "../../src/records/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const items: MyWorkItem[] = [
  { kind: "approval", subject: { type: "invoice", id: "i1" }, ref: "r1" },
  { kind: "assigned", subject: { type: "work_item", id: "w1" }, ref: "w1" },
  { kind: "approval", subject: { type: "invoice", id: "i2" }, ref: "r2" },
];

describe("loadMyWork", () => {
  it("groups the items by kind with a count each", async () => {
    const myWork = vi.fn(() => resolved<readonly MyWorkItem[]>(items));

    const work = await loadMyWork({ myWork }, { pageSize: 10 }).orThrow();

    expect(myWork).toHaveBeenCalledWith({ pageSize: 10 });
    expect(work.items).toEqual(items);
    expect(work.groups.approval.map((item) => item.ref)).toEqual(["r1", "r2"]);
    expect(work.groups.sla).toEqual([]);
    expect(work.counts).toEqual({
      assigned: 1,
      approval: 2,
      reminder: 0,
      mention: 0,
      sla: 0,
    });
  });

  it("keeps only the kinds asked for", async () => {
    const work = await loadMyWork(
      { myWork: () => resolved<readonly MyWorkItem[]>(items) },
      { kinds: ["assigned"] },
    ).orThrow();

    expect(work.items.map((item) => item.ref)).toEqual(["w1"]);
    expect(work.counts.approval).toBe(0);
  });

  it("passes the error through", async () => {
    const result = await loadMyWork({ myWork: () => failed("down") });

    expect(result.ok).toBe(false);
  });
});
