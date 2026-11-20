import { describe, expect, it } from "vitest";

import {
  changedTables,
  leaveAlone,
  tablesToClear,
} from "../../../src/cli/baseline/catalog.ts";

describe("changedTables", () => {
  const before = new Map([
    ["public.a", "2:x"],
    ["public.b", "0:e"],
  ]);

  it("returns tables whose rows changed and skips empty or left-alone ones", () => {
    const after = new Map([
      ["public.a", "3:y"],
      ["public.b", "1:z"],
      ["public.c", "0:e"],
      ["public.d", "1:w"],
    ]);

    expect(
      changedTables(before, after, new Set(["public.d"])).map(
        (t) => `${t.schema}.${t.name}`,
      ),
    ).toEqual(["public.a", "public.b"]);
  });

  it("ignores unchanged tables", () => {
    expect(changedTables(before, new Map(before))).toEqual([]);
  });
});

describe("tablesToClear", () => {
  it("clears only tables that had rows before", () => {
    const before = new Map([
      ["public.a", "2:x"],
      ["public.b", "0:e"],
    ]);

    expect(
      tablesToClear(before, [
        { schema: "public", name: "a" },
        { schema: "public", name: "b" },
        { schema: "public", name: "c" },
      ]),
    ).toEqual([{ schema: "public", name: "a" }]);
  });
});

describe("leaveAlone", () => {
  it("merges the sets and keeps pgmq queue tables out", () => {
    expect([
      ...leaveAlone(
        new Set(["public.a", "pgmq.q_jobs"]),
        new Set(["extensions.x"]),
      ),
    ]).toEqual(["public.a", "extensions.x"]);
  });
});
