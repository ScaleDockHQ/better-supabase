import "temporal-polyfill/global";
import { describe, expect, it } from "vitest";

import { exampleTaxReportFormat } from "../src/tax-report-format.ts";

const report = {
  organizationId: "org-1",
  since: Temporal.PlainDate.from("2026-01-01"),
  until: Temporal.PlainDate.from("2026-03-31"),
  currency: "EUR",
  codes: [],
  boxes: [
    { box: "1a", base: 100_000n, tax: 21_000n },
    { box: "5b", base: 0n, tax: -1050n },
  ],
  salesTax: 21_000n,
  purchaseTax: 1050n,
  netTax: 19_950n,
};

describe("tax report format", () => {
  it("targets API version 1 and has a name", () => {
    expect(exampleTaxReportFormat.apiVersion).toBe(1);
    expect(exampleTaxReportFormat.name).toBe("example-box-csv");
  });

  it("renders one row per box, and the same bytes twice", async () => {
    const first = await exampleTaxReportFormat.render(report);
    const second = await exampleTaxReportFormat.render(report);

    expect(first.ok && first.data.body).toBe(
      "box;base;tax\n1a;1000.00;210.00\n5b;0.00;-10.50\n",
    );
    expect(first).toEqual(second);
  });
});
