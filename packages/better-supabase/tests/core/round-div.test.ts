import { describe, expect, it } from "vitest";

import { roundDiv } from "../../src/core/round-div.ts";

describe("roundDiv", () => {
  it("rounds half away from zero", () => {
    expect(roundDiv(5n, 2n)).toBe(3n);
    expect(roundDiv(-5n, 2n)).toBe(-3n);
    expect(roundDiv(4n, 3n)).toBe(1n);
  });

  it("treats a negative denominator like a negative numerator", () => {
    expect(roundDiv(5n, -2n)).toBe(-3n);
    expect(roundDiv(-5n, -2n)).toBe(3n);
  });
});
