import { describe, expect, it } from "vitest";

import { checkCoverage, routeExists } from "./check-example-coverage.ts";

describe("check-example-coverage", () => {
  it("passes for the catalog and the presets", () => {
    expect(checkCoverage().problems).toEqual([]);
  });

  it("reports a block without an entry", () => {
    const report = checkCoverage(["audit", "not-a-block"]);

    expect(report.problems).toContain(
      'Block "not-a-block" has no entry in block-coverage.ts',
    );
  });

  it("reports a route without a page", () => {
    expect(routeExists("/customers")).toBe(true);
    expect(routeExists("/does-not-exist")).toBe(false);
  });
});
