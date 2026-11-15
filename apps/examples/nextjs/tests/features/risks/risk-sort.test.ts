import { describe, expect, it } from "vitest";

import {
  clickRiskSort,
  formatRiskSort,
  parseRiskSort,
  sortFromSorting,
  sortingOf,
} from "@/features/risks/risk-sort";

describe("parseRiskSort", () => {
  it("reads terms with and without a direction, and drops what the register does not sort by", () => {
    expect(
      parseRiskSort("residualScore:desc,number,title,number:desc"),
    ).toEqual([{ by: "residualScore", direction: "desc" }, { by: "number" }]);
  });

  it("keeps at most three terms", () => {
    expect(parseRiskSort("residualScore,number,nextReviewOn")).toHaveLength(3);
    expect(formatRiskSort(parseRiskSort("number:desc,nextReviewOn"))).toBe(
      "number:desc,nextReviewOn",
    );
  });
});

describe("clickRiskSort", () => {
  it("sorts by the clicked column alone, then flips it", () => {
    expect(clickRiskSort("residualScore", "number", false)).toBe("number");
    expect(clickRiskSort("number", "number", false)).toBe("number:desc");
    expect(clickRiskSort("number:desc", "number", false)).toBe("number:asc");
  });

  it("flips the default sort from its own direction", () => {
    expect(clickRiskSort("residualScore", "residualScore", false)).toBe(
      "residualScore:asc",
    );
  });

  it("adds or flips a column on shift-click", () => {
    expect(clickRiskSort("residualScore", "number", true)).toBe(
      "residualScore,number",
    );
    expect(clickRiskSort("residualScore,number", "number", true)).toBe(
      "residualScore,number:desc",
    );
  });

  it("adds no fourth term", () => {
    expect(
      clickRiskSort("residualScore,number,nextReviewOn", "title", true),
    ).toBe("residualScore,number,nextReviewOn");
  });
});

describe("the header sort state", () => {
  it("round-trips a URL value, and leaves the default out", () => {
    const state = sortingOf("number:desc,nextReviewOn");

    expect(state).toEqual([
      { id: "number", desc: true },
      { id: "nextReviewOn", desc: false },
    ]);
    expect(sortFromSorting(state)).toBe("number:desc,nextReviewOn:asc");
    expect(sortFromSorting(sortingOf("residualScore"))).toBe("residualScore");
    expect(sortFromSorting([])).toBe("residualScore");
  });
});
