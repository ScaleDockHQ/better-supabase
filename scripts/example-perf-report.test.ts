import { describe, expect, it } from "vitest";

import { buildReport, formatLine, scaleLines } from "./example-perf-report.ts";

describe("example-perf-report", () => {
  it("merges the baselines and the measurements of a route", () => {
    const report = buildReport({
      firstLoad: {
        "/[locale]/(app)/customers/page": { raw: 10, gzip: 4, brotli: 3 },
      },
      server: {},
      payload: { "en/customers.html": { raw: 9, gzip: 5, brotli: 4 } },
      budgets: { "/customers": { calls: 3, waves: 1 } },
      coldWarm: { "/customers": { cold: 900, warm: 120, client: 80 } },
    });

    const customers = report.find((line) => line.route === "/customers");

    if (!customers) {
      throw new Error("the manifest has no /customers route");
    }

    expect(customers).toMatchObject({
      firstLoadGzip: 4,
      htmlGzip: 5,
      calls: 3,
      waves: 1,
      coldMs: 900,
      warmMs: 120,
      clientMs: 80,
    });

    expect(formatLine(customers)).toContain("cold 900 ms");
  });

  it("leaves a dash for a number it has not measured", () => {
    const report = buildReport({
      firstLoad: {},
      server: {},
      payload: {},
      budgets: {},
      coldWarm: {},
    });

    const [first] = report;

    if (!first) {
      throw new Error("the manifest is empty");
    }

    expect(formatLine(first)).toContain("calls -/");
  });

  it("reads the SCALE lines out of pgTAP output", () => {
    expect(
      scaleLines(
        "# SCALE_MS list_first_page=12\nok 1\n# SCALE_CALLS list_first_page=2\nnoise",
      ),
    ).toEqual(["SCALE_MS list_first_page=12", "SCALE_CALLS list_first_page=2"]);
  });
});
