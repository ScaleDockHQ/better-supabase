import { describe, expect, it } from "vitest";

import {
  durationsFromJson,
  overBaseline,
  slowTestsFromJson,
  slowestFilesSummary,
} from "./unit-durations.ts";

const report = JSON.stringify({
  testResults: [
    {
      name: "/work/packages/better-supabase/tests/sql/a.test.ts",
      startTime: 1000,
      endTime: 41_000.4,
      assertionResults: [
        { fullName: "a renders", duration: 11_000 },
        { fullName: "a reads", duration: 2000 },
        { fullName: "a skips", duration: null },
      ],
    },
  ],
});

describe("durationsFromJson", () => {
  it("keeps the path under the library and rounds to milliseconds", () => {
    expect(durationsFromJson(report)).toEqual([
      { file: "tests/sql/a.test.ts", durationMs: 40_000 },
    ]);
  });

  it("rejects a report without test results", () => {
    expect(() => durationsFromJson("{}")).toThrow("testResults");
  });
});

describe("slowTestsFromJson", () => {
  it("lists the tests over half the 20 second timeout", () => {
    expect(slowTestsFromJson(report)).toEqual([
      { file: "tests/sql/a.test.ts", test: "a renders", durationMs: 11_000 },
    ]);
  });
});

describe("overBaseline", () => {
  const rows = [
    { file: "tests/slow.test.ts", durationMs: 40_000 },
    { file: "tests/noisy.test.ts", durationMs: 2000 },
    { file: "tests/new.test.ts", durationMs: 90_000 },
  ];

  it("flags a file 50% and five seconds over its baseline", () => {
    const baseline = new Map([
      ["tests/slow.test.ts", 20_000],
      ["tests/noisy.test.ts", 500],
    ]);

    expect(overBaseline(rows, baseline)).toEqual([rows[0]]);
  });

  it("passes a file within half its baseline", () => {
    expect(
      overBaseline(rows, new Map([["tests/slow.test.ts", 30_000]])),
    ).toEqual([]);
  });
});

describe("slowestFilesSummary", () => {
  it("lists the longest files first with their baseline", () => {
    const summary = slowestFilesSummary(
      [
        { file: "tests/a.test.ts", durationMs: 500 },
        { file: "tests/b.test.ts", durationMs: 2500 },
      ],
      new Map([["tests/b.test.ts", 2000]]),
    );

    expect(summary).toContain("| `tests/b.test.ts` | 2.5 | 2.0 |");
    expect(summary).toContain("| `tests/a.test.ts` | 0.5 | new |");
    expect(summary.indexOf("tests/b.test.ts")).toBeLessThan(
      summary.indexOf("tests/a.test.ts"),
    );
  });
});
