import { describe, expect, it } from "vitest";

import type { RiskRow } from "@/features/risks/risk-rows";

import { sortRisks } from "@/features/risks/risk-reads";

function risk(
  number: string,
  score: number | null,
  review: string | null,
): RiskRow {
  return {
    id: number,
    number,
    title: number,
    category: "quality",
    status: "assessed",
    band: null,
    tone: null,
    score,
    nextReviewOn: review,
  };
}

const rows = [
  risk("RSK-0002", 20, "2027-03-01"),
  risk("RSK-0010", 20, "2027-01-01"),
  risk("RSK-0001", 5, null),
  risk("RSK-0003", null, "2027-02-01"),
];

describe("sortRisks", () => {
  it("orders by every term, then by number", () => {
    const sorted = sortRisks(rows, [
      { by: "residualScore" },
      { by: "nextReviewOn", direction: "asc" },
    ]);

    expect(sorted.map((row) => row.number)).toEqual([
      "RSK-0010",
      "RSK-0002",
      "RSK-0001",
      "RSK-0003",
    ]);
  });

  it("reads a later term in its own direction", () => {
    const sorted = sortRisks(rows, [
      { by: "residualScore" },
      { by: "nextReviewOn", direction: "desc" },
    ]);

    expect(sorted.map((row) => row.number).slice(0, 2)).toEqual([
      "RSK-0002",
      "RSK-0010",
    ]);
  });

  it("sorts numbers naturally", () => {
    const sorted = sortRisks(rows, [{ by: "number" }]);

    expect(sorted.map((row) => row.number)).toEqual([
      "RSK-0001",
      "RSK-0002",
      "RSK-0003",
      "RSK-0010",
    ]);
  });
});
