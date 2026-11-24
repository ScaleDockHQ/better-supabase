import { describe, expect, it } from "vitest";

import type { UnitTimes } from "./unit-durations.ts";

import { findings, grew, slowestFilesSummary } from "./unit-durations.ts";

const times: UnitTimes = {
  files: {
    "tests/slow.test.ts": 40_000,
    "tests/noisy.test.ts": 2000,
    "tests/new.test.ts": 90_000,
  },
  slowTests: [
    { id: "tests/slow.test.ts > known", durationMs: 12_000, timeoutMs: 20_000 },
    { id: "tests/slow.test.ts > fresh", durationMs: 11_000, timeoutMs: 20_000 },
  ],
};

describe("grew", () => {
  it("needs 50% and five seconds over the baseline", () => {
    expect(grew(40_000, 20_000)).toBe(true);
    expect(grew(40_000, 30_000)).toBe(false);
    expect(grew(2000, 500)).toBe(false);
  });
});

describe("findings", () => {
  it("flags a grown file and a test past half its timeout that no baseline lists", () => {
    const found = findings(
      times,
      new Map([
        ["tests/slow.test.ts", 20_000],
        ["tests/noisy.test.ts", 500],
      ]),
      new Map([["tests/slow.test.ts > known", 11_000]]),
    );

    expect(found).toHaveLength(2);
    expect(found[0]).toContain("`tests/slow.test.ts` took 40.0 s");
    expect(found[1]).toContain("`tests/slow.test.ts > fresh` took 11.0 s");
  });
});

describe("slowestFilesSummary", () => {
  it("lists the longest files first with their baseline", () => {
    const summary = slowestFilesSummary(
      times,
      new Map([["tests/slow.test.ts", 20_000]]),
    );

    expect(summary).toContain("| `tests/slow.test.ts` | 40.0 | 20.0 |");
    expect(summary).toContain("| `tests/new.test.ts` | 90.0 | new |");
    expect(summary.indexOf("tests/new.test.ts")).toBeLessThan(
      summary.indexOf("tests/slow.test.ts"),
    );
  });
});
