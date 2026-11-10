import { describe, expect, it } from "vitest";

import { keptMeasurement } from "./keep-baseline.ts";

const room = (before: number): number => Math.max(256, before * 0.05);

describe("keptMeasurement", () => {
  it("keeps the committed number inside the slack", () => {
    expect(keptMeasurement(10_000, 10_200, room)).toBe(10_000);
  });

  it("takes a measurement that grew past the slack", () => {
    expect(keptMeasurement(10_000, 11_000, room)).toBe(11_000);
  });

  it("takes a measurement that fell past the slack", () => {
    expect(keptMeasurement(10_000, 9000, room)).toBe(9000);
  });

  it("records a new entry", () => {
    expect(keptMeasurement(undefined, 40, room)).toBe(40);
  });
});
