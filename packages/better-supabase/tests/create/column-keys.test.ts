import { describe, expect, test } from "vitest";

import {
  boundError,
  optionError,
  withBounds,
} from "../../src/create/column-keys.ts";

describe("optionError", () => {
  test("refuses empty, long, control, repeated and surplus options", () => {
    expect(optionError([], "")).toBe("Enter an option.");
    expect(optionError([], "x".repeat(500))).toMatch(/at most/u);
    expect(optionError([], "a\nb")).toMatch(/line breaks/u);
    expect(optionError(["a"], "a")).toMatch(/already/u);
    expect(
      optionError(
        Array.from({ length: 500 }, (_, index) => `o${index}`),
        "new",
      ),
    ).toMatch(/at most/u);
    expect(optionError(["a"], "b")).toBeUndefined();
  });
});

describe("boundError", () => {
  test("checks the number against the column type and the other bound", () => {
    expect(boundError({ type: "integer" }, "min", " ")).toBeUndefined();
    expect(boundError({ type: "integer" }, "min", "x")).toBe("Enter a number.");
    expect(boundError({ type: "text" }, "max", "-1")).toMatch(/length/u);
    expect(boundError({ type: "integer" }, "max", "1.5")).toMatch(/whole/u);
    expect(boundError({ type: "integer", max: 3 }, "min", "5")).toMatch(
      /below/u,
    );
    expect(boundError({ type: "integer", min: 3 }, "max", "1")).toMatch(
      /above/u,
    );
    expect(boundError({ type: "integer", min: 1 }, "max", "9")).toBeUndefined();
  });
});

describe("withBounds", () => {
  test("replaces both bounds and removes the ones left out", () => {
    expect(withBounds({ type: "integer", min: 1, max: 2 }, { min: 5 })).toEqual(
      { type: "integer", min: 5 },
    );
    expect(withBounds({ type: "integer" }, { min: 1, max: 9 })).toEqual({
      type: "integer",
      min: 1,
      max: 9,
    });
  });
});
