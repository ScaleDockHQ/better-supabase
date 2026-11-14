import { describe, expect, it } from "vitest";

import { TARGETS, seedCalls } from "./seed-entity-pages.ts";

const [target] = TARGETS;

describe("seed-entity-pages", () => {
  it("calls the create function once per generated row", () => {
    const calls = seedCalls(target!, "tenant-1");

    expect(calls).toHaveLength(target!.seed.rows.length);
    expect(calls[0]?.sql).toContain("better_supabase.create_work_order");
    expect(calls[0]?.title).toBe("Title 1");

    expect(calls[0]?.values).toEqual([
      "tenant-1",
      JSON.stringify(target!.seed.rows[0]),
    ]);
  });

  it("adds nothing for a tier the seed does not belong to", () => {
    expect(seedCalls(target!, "tenant-1", "l")).toEqual([]);
  });

  it("refuses a row with no title", () => {
    const seed = { ...target!.seed, rows: [{ name: "x" }] };

    expect(() => seedCalls({ ...target!, seed }, "tenant-1")).toThrow(
      "needs a title",
    );
  });
});
