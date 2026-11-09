import { describe, expect, it } from "vitest";

import { planCostRegressed } from "../../src/sql/rls-cost.ts";

describe("RLS plan cost", () => {
  it("fails when the cost grows by more than 20 percent", () => {
    expect(planCostRegressed(100, 120)).toBe(false);
    expect(planCostRegressed(100, 120.01)).toBe(true);
    expect(planCostRegressed(100, 80)).toBe(false);
  });
});
