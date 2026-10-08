import { Temporal } from "temporal-polyfill";
import { describe, expect, it } from "vitest";

import { shareStructure } from "../../src/core/share.ts";

describe("shareStructure", () => {
  it("returns prev when nothing changed", () => {
    const prev = {
      ok: true,
      data: [{ id: 1, at: Temporal.Instant.from("2026-01-01T00:00:00Z") }],
    };
    const next = {
      ok: true,
      data: [{ id: 1, at: Temporal.Instant.from("2026-01-01T00:00:00Z") }],
    };
    expect(shareStructure(prev, next)).toBe(prev);
  });

  it("keeps unchanged rows by id, even when reordered", () => {
    const a = { id: "a", name: "A" };
    const b = { id: "b", name: "B" };
    const prev = [a, b];
    const next = [
      { id: "b", name: "B" },
      { id: "a", name: "A2" },
      { id: "c", name: "C" },
    ];
    const shared = shareStructure(prev, next);
    expect(shared).not.toBe(prev);
    expect(shared[0]).toBe(b);
    expect(shared[1]).toEqual({ id: "a", name: "A2" });
    expect(shared[1]).not.toBe(a);
    expect(shared[2]).toBe(next[2]);
  });

  it("matches items without an id by position", () => {
    const prev = [{ n: 1 }, { n: 2 }];
    const shared = shareStructure(prev, [{ n: 1 }, { n: 3 }]);
    expect(shared[0]).toBe(prev[0]);
    expect(shared[1]).toEqual({ n: 3 });
  });

  it("treats added or removed keys and different types as changes", () => {
    const prev = { a: 1 };
    expect(shareStructure(prev, { a: 1, b: undefined })).not.toBe(prev);
    expect(shareStructure({ a: 1, b: 2 }, { a: 1 })).toEqual({ a: 1 });
    expect(shareStructure([1], { 0: 1 })).toEqual({ 0: 1 });
    expect(shareStructure(undefined, { a: 1 })).toEqual({ a: 1 });
    expect(shareStructure(new Date(0), new Date(1))).toEqual(new Date(1));
    const date = new Date(0);
    expect(shareStructure(date, new Date(0))).toBe(date);
  });
});

describe("shareStructure with class instances", () => {
  it("keeps equal Temporal values and never shares objects without toJSON", () => {
    const at = Temporal.Instant.from("2026-01-01T00:00:00.000000001Z");
    expect(
      shareStructure(
        at,
        Temporal.Instant.from("2026-01-01T00:00:00.000000001Z"),
      ),
    ).toBe(at);
    expect(
      shareStructure(
        at,
        Temporal.Instant.from("2026-01-01T00:00:00.000000002Z"),
      ),
    ).not.toBe(at);
    const bytes = new Uint8Array([1]);
    expect(shareStructure(bytes, new Uint8Array([1]))).not.toBe(bytes);
  });
});
