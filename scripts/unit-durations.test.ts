import { describe, expect, it } from "vitest";

import { durationsFromJson, slowestFilesSummary } from "./unit-durations.ts";

describe("durationsFromJson", () => {
  it("keeps the path under the library and rounds to milliseconds", () => {
    expect(
      durationsFromJson(
        JSON.stringify({
          testResults: [
            {
              name: "/work/packages/better-supabase/tests/sql/a.test.ts",
              startTime: 1000,
              endTime: 2500.4,
            },
          ],
        }),
      ),
    ).toEqual([{ file: "tests/sql/a.test.ts", durationMs: 1500 }]);
  });

  it("rejects a report without test results", () => {
    expect(() => durationsFromJson("{}")).toThrow("testResults");
  });
});

describe("slowestFilesSummary", () => {
  it("lists the longest files first", () => {
    const summary = slowestFilesSummary([
      { file: "tests/a.test.ts", durationMs: 500 },
      { file: "tests/b.test.ts", durationMs: 2500 },
    ]);

    expect(summary).toContain("| `tests/b.test.ts` | 2.5 |");
    expect(summary.indexOf("tests/b.test.ts")).toBeLessThan(
      summary.indexOf("tests/a.test.ts"),
    );
  });
});
