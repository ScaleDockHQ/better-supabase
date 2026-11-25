import { describe, expect, it } from "vitest";

import type { UnitTimes } from "./unit-durations.ts";

import {
  findings,
  grew,
  slowestFilesSummary,
  slowestOf,
} from "./unit-durations.ts";

const times: UnitTimes = {
  files: {
    "tests/slow.test.ts": 40_000,
    "tests/noisy.test.ts": 2000,
    "tests/new.test.ts": 90_000,
  },
  slowTests: [
    { id: "tests/slow.test.ts > known", durationMs: 12_000, timeoutMs: 20_000 },
    { id: "tests/slow.test.ts > fresh", durationMs: 11_000, timeoutMs: 20_000 },
    { id: "tests/slow.test.ts > hovers", durationMs: 9000, timeoutMs: 20_000 },
  ],
};

describe("grew", () => {
  it("needs twice the baseline and five seconds over it", () => {
    expect(grew(41_000, 20_000)).toBe(true);
    expect(grew(40_000, 30_000)).toBe(false);
    expect(grew(2000, 500)).toBe(false);
  });
});

describe("findings", () => {
  it("flags a grown file and only an unlisted test past half its timeout", () => {
    const found = findings(
      times,
      new Map([
        ["tests/slow.test.ts", 19_000],
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

describe("slowestOf", () => {
  it("keeps the slowest time of each file and slow test over the runs", () => {
    const { files, slowTests } = slowestOf([
      times,
      {
        files: { "tests/slow.test.ts": 50_000, "tests/noisy.test.ts": 1000 },
        slowTests: [
          {
            id: "tests/slow.test.ts > known",
            durationMs: 9000,
            timeoutMs: 20_000,
          },
        ],
      },
    ]);

    expect(files.get("tests/slow.test.ts")).toBe(50_000);
    expect(files.get("tests/noisy.test.ts")).toBe(2000);
    expect(slowTests.get("tests/slow.test.ts > known")).toBe(12_000);
    expect(slowTests.get("tests/slow.test.ts > fresh")).toBe(11_000);
  });
});
