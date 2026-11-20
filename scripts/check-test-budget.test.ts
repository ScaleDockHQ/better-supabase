import { describe, expect, it } from "vitest";

import { countLines, overBudget } from "./check-test-budget.ts";

describe("test budget", () => {
  it("counts newline-terminated lines", () => {
    expect(countLines("")).toBe(0);
    expect(countLines("a\nb\n")).toBe(2);
  });

  it("allows the margin and nothing beyond it", () => {
    expect(overBudget(1020, 1000)).toBe(false);
    expect(overBudget(1021, 1000)).toBe(true);
  });
});
