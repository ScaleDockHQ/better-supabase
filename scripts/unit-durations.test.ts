import { describe, expect, it } from "vitest";

import type { Budget, UnitTimes } from "./unit-durations.ts";

import {
  addedTo,
  budgetOf,
  findings,
  grew,
  limitOf,
  slowestFilesSummary,
  testFindings,
} from "./unit-durations.ts";

const LIB = "packages/better-supabase/tests";

const times: UnitTimes = {
  coverage: true,
  files: {
    [`${LIB}/slow.test.ts`]: 40_000,
    [`${LIB}/noisy.test.ts`]: 2000,
    [`${LIB}/new.test.ts`]: 90_000,
    "tests/validation-crm/src/a.test.ts": 5000,
  },
  slowTests: [
    { id: "known", durationMs: 12_000, timeoutMs: 20_000 },
    { id: "fresh", durationMs: 11_000, timeoutMs: 20_000 },
    { id: "hovers", durationMs: 9000, timeoutMs: 20_000 },
    { id: "raised", durationMs: 31_000, timeoutMs: 120_000 },
  ],
};

const budget: Budget = {
  totalMs: 110_000,
  files: { [`${LIB}/slow.test.ts`]: 19_000, [`${LIB}/noisy.test.ts`]: 500 },
  slowTests: { known: 11_000 },
};

describe("limitOf", () => {
  it("is half the timeout, capped at half of 20 seconds", () => {
    expect(limitOf(10_000)).toBe(5000);
    expect(limitOf(120_000)).toBe(10_000);
  });
});

describe("grew", () => {
  it("needs twice the baseline and five seconds over it", () => {
    expect(grew(41_000, 20_000)).toBe(true);
    expect(grew(40_000, 30_000)).toBe(false);
    expect(grew(2000, 500)).toBe(false);
  });
});

describe("testFindings", () => {
  it("flags an unlisted test past its limit, a raised timeout included", () => {
    const found = testFindings(times, budget);

    expect(found).toHaveLength(2);
    expect(found[0]).toContain("`fresh` took 11.0 s");
    expect(found[1]).toContain("`raised` took 31.0 s");
  });
});

describe("findings", () => {
  it("flags a grown file and a summed time 15% over the budget", () => {
    const found = findings(times, budget);

    expect(found[0]).toContain(`\`${LIB}/slow.test.ts\` took 40.0 s`);
    expect(found[1]).toContain("Summed test time over budget: 132.0 s");
  });

  it("passes a summed time within 15% of the budget", () => {
    expect(
      findings(times, { ...budget, totalMs: 115_000 }).some((line) =>
        line.startsWith("Summed"),
      ),
    ).toBe(false);
  });
});

describe("budgetOf", () => {
  it("keeps the slowest file, test and library total over the runs", () => {
    const next = budgetOf([
      times,
      {
        coverage: true,
        files: {
          [`${LIB}/slow.test.ts`]: 50_000,
          [`${LIB}/noisy.test.ts`]: 1000,
        },
        slowTests: [{ id: "known", durationMs: 9000, timeoutMs: 20_000 }],
      },
    ]);

    expect(next.totalMs).toBe(132_000);
    expect(next.files[`${LIB}/slow.test.ts`]).toBe(50_000);
    expect(next.files[`${LIB}/noisy.test.ts`]).toBe(2000);
    expect(next.slowTests["known"]).toBe(12_000);
    expect(next.slowTests["raised"]).toBe(31_000);
  });
});

describe("slowestFilesSummary", () => {
  it("lists the longest files first with their baseline", () => {
    const summary = slowestFilesSummary(times, budget);

    expect(summary).toContain(`| \`${LIB}/slow.test.ts\` | 40.0 | 19.0 |`);
    expect(summary).toContain(`| \`${LIB}/new.test.ts\` | 90.0 | new |`);
    expect(summary.indexOf("new.test.ts")).toBeLessThan(
      summary.indexOf("slow.test.ts"),
    );
  });
});

describe("addedTo", () => {
  it("adds what has no baseline and keeps every listed one", () => {
    const next = addedTo(budget, [times]);

    expect(next.totalMs).toBe(budget.totalMs);
    expect(next.files[`${LIB}/slow.test.ts`]).toBe(19_000);
    expect(next.files[`${LIB}/new.test.ts`]).toBe(90_000);
    expect(next.slowTests).toMatchObject({ known: 11_000, fresh: 11_000 });
  });
});
