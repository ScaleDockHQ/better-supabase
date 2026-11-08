import { describe, expect, it } from "vitest";

import {
  createReadTracker,
  readsHold,
} from "../../../src/sql/pipeline/read-tracking.ts";

type Input = Record<string, unknown>;

/** Runs `read` on a tracked copy of `input` and returns the reads it made. */
function track(input: Input, read: (view: Input) => unknown) {
  const tracker = createReadTracker();
  read(tracker.wrap("layout", input));

  return tracker;
}

const holds = (
  tracker: ReturnType<typeof track>,
  layout: Input,
  installed: readonly string[] = [],
): boolean => readsHold(tracker.reads(), { layout, installed });

describe("createReadTracker", () => {
  it("holds for the input it read and for changes it did not read", () => {
    const input = { a: { x: 1, y: 2 }, b: 3 };
    const tracker = track(input, (view) => (view["a"] as Input)["x"]);

    expect(holds(tracker, input)).toBe(true);
    expect(holds(tracker, { a: { x: 1, y: 99 }, b: 4 })).toBe(true);
    expect(holds(tracker, { a: { x: 2, y: 2 }, b: 3 })).toBe(false);
    // The object the read went through must still be an object.
    expect(holds(tracker, { a: 1, b: 3 })).toBe(false);
    expect(holds(tracker, {})).toBe(false);
  });

  it("records an absent key, so adding it invalidates", () => {
    const tracker = track({ a: 1 }, (view) => view["missing"]);

    expect(holds(tracker, { a: 2 })).toBe(true);
    expect(holds(tracker, { missing: undefined })).toBe(false);
    expect(holds(tracker, { missing: 0 })).toBe(false);
  });

  it("records `in`, enumeration and spreading", () => {
    const has = track({ a: 1 }, (view) => "a" in view);
    expect(holds(has, { a: 5 })).toBe(true);
    expect(holds(has, { b: 1 })).toBe(false);

    const keys = track({ a: 1, b: 2 }, (view) => Object.keys(view));
    expect(holds(keys, { a: 9, b: 9 })).toBe(true);
    expect(holds(keys, { a: 1, b: 2, c: 3 })).toBe(false);
    expect(holds(keys, { b: 2, a: 1 })).toBe(false);

    const spread = track({ a: 1, b: { c: 2 } }, (view) => ({ ...view }));
    expect(holds(spread, { a: 1, b: { c: 99 } })).toBe(true);
    expect(holds(spread, { a: 2, b: { c: 2 } })).toBe(false);
  });

  it("reads arrays by index, length and method", () => {
    const find = track({ list: ["a", "b", "c"] }, (view) =>
      (view["list"] as string[]).indexOf("b"),
    );

    expect(holds(find, { list: ["a", "b", "z"] })).toBe(true);
    expect(holds(find, { list: ["x", "b", "c"] })).toBe(false);

    const all = track({ list: [1, 2] }, (view) =>
      JSON.stringify((view["list"] as number[]).map((n) => n + 1)),
    );

    expect(holds(all, { list: [1, 2] })).toBe(true);
    expect(holds(all, { list: [1, 2, 3] })).toBe(false);
    expect(Array.isArray(createReadTracker().wrap("layout", [1]))).toBe(true);
  });

  it("tracks the installed names as a second root", () => {
    const tracker = createReadTracker();
    const installed = tracker.wrap("installed", ["audit", "tasks"]);
    installed.indexOf("tasks");

    expect(
      readsHold(tracker.reads(), { layout: {}, installed: ["audit", "tasks"] }),
    ).toBe(true);
    expect(
      readsHold(tracker.reads(), { layout: {}, installed: ["tasks", "audit"] }),
    ).toBe(false);
  });

  it("works on a frozen input and returns the real values", () => {
    const input = Object.freeze({
      list: Object.freeze([1, 2]),
      deep: Object.freeze({ n: 1 }),
    });

    const tracker = createReadTracker();
    const view = tracker.wrap("layout", input);

    expect(JSON.stringify(view)).toBe(JSON.stringify(input));
    expect(Object.keys(view)).toEqual(["list", "deep"]);
  });

  it("records a map as a whole and refuses a function", () => {
    const map = new Map([["a", 1]]);

    const mapped = track({ m: map }, (view) =>
      (view["m"] as Map<string, number>).get("a"),
    );

    expect(holds(mapped, { m: new Map([["a", 1]]) })).toBe(true);
    expect(holds(mapped, { m: new Map([["a", 2]]) })).toBe(false);
    expect(mapped.uncacheable()).toBe(false);

    const fn = track({ f: () => 1 }, (view) => (view["f"] as () => number)());
    expect(fn.uncacheable()).toBe(true);

    const instance = track(
      {
        d: new (class Box {
          n = 1;
        })(),
      },
      (view) => view["d"],
    );

    expect(instance.uncacheable()).toBe(true);
  });

  it("refuses a render that writes to its input", () => {
    const input = { a: 1 };

    const tracker = track(input, (view) => {
      view["a"] = 2;
    });

    expect(tracker.uncacheable()).toBe(true);
  });

  it("keeps one read per path and kind", () => {
    const tracker = track({ a: 1 }, (view) => {
      void view["a"];
      void view["a"];
    });

    expect(
      tracker.reads().filter((read) => read.kind === "value"),
    ).toHaveLength(1);
  });

  it("passes symbol keys and inherited members through without recording them", () => {
    const tracker = createReadTracker();
    const list = tracker.wrap("layout", [1, 2]);

    expect([...list]).toEqual([1, 2]);
    expect(String(tracker.wrap("layout", { a: 1 }))).toBe("[object Object]");
    expect(tracker.uncacheable()).toBe(false);
  });

  it("refuses a render that defines or deletes a property of its input", () => {
    const defined = createReadTracker();
    Object.defineProperty(defined.wrap("layout", { a: 1 }), "b", { value: 2 });
    expect(defined.uncacheable()).toBe(true);

    const deleted = createReadTracker();
    delete (deleted.wrap("layout", { a: 1 }) as Input)["a"];
    expect(deleted.uncacheable()).toBe(true);
  });

  it("sees the kind of a null, a function and a primitive at a path", () => {
    const tracker = track({ a: null, b: "x" }, (view) => [
      view["a"],
      view["b"],
    ]);

    expect(holds(tracker, { a: null, b: "x" })).toBe(true);
    expect(holds(tracker, { a: {}, b: "x" })).toBe(false);
    expect(holds(tracker, { a: null, b: ["x"] })).toBe(false);
  });

  it("keeps long values as a digest and still tells them apart", () => {
    const long = "x".repeat(200);
    const tracker = track({ a: long }, (view) => view["a"]);

    expect(holds(tracker, { a: long })).toBe(true);
    expect(holds(tracker, { a: `${long}y` })).toBe(false);
    expect(tracker.reads().every((read) => read.seen.length < 80)).toBe(true);
  });

  it("does not wrap a value that is not a plain object or array", () => {
    const tracker = createReadTracker();
    const date = new Date(0);

    expect(tracker.wrap("layout", date)).toBe(date);
    expect(tracker.wrap("layout", 5)).toBe(5);
  });
});
