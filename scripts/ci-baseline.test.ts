import { describe, expect, it } from "vitest";

import { percentile, splitJob } from "./ci-baseline.ts";

describe("percentile", () => {
  it("returns the nearest rank and 0 for no values", () => {
    expect(percentile([], 50)).toBe(0);
    expect(percentile([10, 20, 30, 40], 50)).toBe(20);
    expect(percentile([10, 20, 30, 40], 95)).toBe(40);
  });
});

describe("splitJob", () => {
  it("separates waiting, setup steps and the rest", () => {
    const at = (second: number): string =>
      new Date(Date.UTC(2026, 0, 1, 0, 0, second)).toISOString();

    expect(
      splitJob({
        name: "unit",
        conclusion: "success",
        created_at: at(0),
        started_at: at(3),
        completed_at: at(103),
        steps: [
          { name: "Set up job", started_at: at(3), completed_at: at(10) },
          { name: "Run tests", started_at: at(10), completed_at: at(100) },
        ],
      }),
    ).toEqual({ waiting: 3, setup: 7, running: 93 });
  });
});
