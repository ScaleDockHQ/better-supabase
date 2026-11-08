import { describe, expect, it } from "vitest";

import { renderKey } from "../../../src/sql/pipeline/render-key.ts";

describe("renderKey", () => {
  it("is the same for the same input in any key order", () => {
    const a = renderKey(["tasks"], { prefix: "010", dir: "schemas" }, "1");
    const b = renderKey(["tasks"], { dir: "schemas", prefix: "010" }, "1");

    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(a).toBe(b);
  });

  it("changes with the names, the layout and the version", () => {
    const base = renderKey(["tasks"], {}, "1");

    expect(renderKey(["tasks", "files"], {}, "1")).not.toBe(base);
    expect(renderKey(["tasks"], { dir: "x" }, "1")).not.toBe(base);
    expect(renderKey(["tasks"], {}, "2")).not.toBe(base);
  });

  it("covers maps, sets and nested lists in sorted order", () => {
    const key = (layout: object): string | undefined =>
      renderKey([], layout, "1");

    expect(
      key({
        a: new Map([
          ["b", 1],
          ["a", 2],
        ]),
      }),
    ).toBe(
      key({
        a: new Map([
          ["a", 2],
          ["b", 1],
        ]),
      }),
    );

    expect(key({ a: new Set([1, 2]) })).toBe(key({ a: new Set([1, 2]) }));
    expect(key({ a: new Set([1]) })).not.toBe(key({ a: new Map([[1, 1]]) }));
    expect(key({ a: [1, [2, { b: undefined }]] })).toBeDefined();
    expect(key({ a: null })).not.toBe(key({ a: undefined }));
  });

  it("returns undefined for state it can't cover", () => {
    class Box {
      readonly value = 1;
    }

    const key = (layout: object): string | undefined =>
      renderKey([], layout, "1");

    expect(key({ a: () => 1 })).toBeUndefined();
    expect(key({ a: [() => 1] })).toBeUndefined();
    expect(key({ a: Symbol("x") })).toBeUndefined();
    expect(key({ a: new Box() })).toBeUndefined();
    expect(key({ a: new Map([["k", () => 1]]) })).toBeUndefined();
    expect(key({ a: new Set([() => 1]) })).toBeUndefined();
    expect(key({ a: Object.create(null) })).toBeDefined();
  });
});
