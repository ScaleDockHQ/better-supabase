import { describe, expect, it } from "vitest";

import type { TaxReportFormat } from "../../../src/blocks/accounting/index.ts";

import {
  createAccounting,
  taxReportFormatOf,
} from "../../../src/blocks/accounting/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";

const ENTRY = {
  id: "e1",
  organizationId: "org-1",
  journalId: "j1",
  entryDate: "2026-01-15",
  status: "posted",
  sourceType: "invoice",
  sourceId: "inv-1",
  total: "12100",
  createdAt: AT,
  updatedAt: AT,
  lines: [],
};

const TAX_REPORT = {
  organizationId: "org-1",
  since: "2026-01-01",
  until: "2026-03-31",
  currency: "EUR",
  codes: [
    {
      taxCodeId: "t1",
      code: "VAT21",
      name: "VAT 21%",
      kind: "sales",
      rateBps: 2100,
      reportBoxes: ["1a"],
      base: "10000",
      tax: "2100",
    },
    {
      taxCodeId: "t2",
      code: "VATIN",
      name: "Input VAT",
      kind: "purchase",
      rateBps: "2100",
      base: "1000",
      tax: "210",
    },
  ],
  boxes: [{ box: "1a", base: "10000", tax: "2100" }],
  salesTax: "2100",
  purchaseTax: "210",
  netTax: "1890",
};

const BUDGET = {
  id: "b1",
  organizationId: "org-1",
  name: "Plan 2026",
  fiscalYear: 2026,
  status: "draft",
  total: "300000",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  lines: [
    {
      id: "bl1",
      accountId: "a1",
      accountCode: "8000",
      periodNumber: 1,
      dimensions: { department: "sales" },
      amount: "300000",
    },
  ],
};

const VERSUS = {
  budgetId: "b1",
  name: "Plan 2026",
  fiscalYear: 2026,
  periodNumber: null,
  lines: [
    {
      accountId: "a1",
      code: "8000",
      name: "Revenue",
      type: "income",
      dimensions: {},
      budget: "300000",
      actual: "250000",
      variance: "-50000",
    },
  ],
  budget: "300000",
  actual: "250000",
};

describe("accounting postings", () => {
  it("books a source once and reads nothing for a source with nothing to book", async () => {
    const t = fieldsTransport({
      post_accounting_source: (args) =>
        args["source_id"] === "inv-1" ? ENTRY : null,
    });

    const books = createAccounting({ transport: t });

    const entry = await books.postSource("invoice", "inv-1").orThrow();
    const none = await books.postSource("invoice", "draft-1").orThrow();

    expect(entry?.sourceType).toBe("invoice");
    expect(entry?.status).toBe("posted");
    expect(none).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "post_accounting_source",
      { source_type: "invoice", source_id: "inv-1" },
    ]);
  });

  it("reads the tax report per code and box", async () => {
    const t = fieldsTransport({ accounting_tax_report: () => TAX_REPORT });
    const books = createAccounting({ transport: t });

    const report = await books
      .taxReport(
        "org-1",
        Temporal.PlainDate.from("2026-01-01"),
        Temporal.PlainDate.from("2026-03-31"),
      )
      .orThrow();

    expect(t.calls).toEqual([
      [
        "accounting_tax_report",
        { tenant: "org-1", since: "2026-01-01", until: "2026-03-31" },
      ],
    ]);
    expect(report.since.toString()).toBe("2026-01-01");
    expect(report.codes[0]).toMatchObject({ rateBps: 2100, base: 10_000n });
    expect(report.codes[1]?.reportBoxes).toEqual([]);
    expect(report.codes[1]?.rateBps).toBe(2100);
    expect(report.boxes).toEqual([{ box: "1a", base: 10_000n, tax: 2100n }]);
    expect(report.netTax).toBe(1890n);
  });

  it("reads an empty tax report", async () => {
    const t = fieldsTransport({
      accounting_tax_report: () => ({
        ...TAX_REPORT,
        codes: null,
        boxes: null,
        salesTax: "0",
        purchaseTax: "0",
        netTax: "0",
      }),
    });

    const report = await createAccounting({ transport: t })
      .taxReport(
        "org-1",
        Temporal.PlainDate.from("2026-01-01"),
        Temporal.PlainDate.from("2026-03-31"),
      )
      .orThrow();

    expect(report.codes).toEqual([]);
    expect(report.boxes).toEqual([]);
  });

  it("saves, reads and lists budgets and compares them with actuals", async () => {
    const t = fieldsTransport({
      save_accounting_budget: () => BUDGET,
      get_accounting_budget: (args) =>
        args["budget_id"] === "b1" ? BUDGET : null,
      list_accounting_budgets: () => [
        { ...BUDGET, lines: undefined, createdBy: null },
      ],
      accounting_budget_vs_actual: (args) =>
        args["period_number"] === 1 ? { ...VERSUS, periodNumber: 1 } : VERSUS,
    });

    const books = createAccounting({ transport: t });

    const saved = await books
      .saveBudget("org-1", {
        name: "Plan 2026",
        fiscalYear: 2026,
        lines: [
          {
            accountCode: "8000",
            periodNumber: 1,
            amount: 300_000n,
            dimensions: { department: "sales" },
          },
          { accountId: "a1", periodNumber: 2, amount: 0n },
        ],
      })
      .orThrow();

    await books
      .saveBudget("org-1", {
        name: "Plan 2026",
        fiscalYear: 2026,
        status: "approved",
        budgetId: "b1",
      })
      .orThrow();

    const read = await books.budget("b1").orThrow();
    const missing = await books.budget("b2").orThrow();
    const listed = await books.budgets("org-1", 2026).orThrow();

    await books.budgets("org-1").orThrow();

    const year = await books.budgetVsActual("b1").orThrow();
    const period = await books.budgetVsActual("b1", 1).orThrow();

    expect(saved.total).toBe(300_000n);
    expect(saved.lines?.[0]).toMatchObject({
      accountCode: "8000",
      amount: 300_000n,
      dimensions: { department: "sales" },
    });
    expect(read?.createdBy).toBe("u1");
    expect(missing).toBeUndefined();
    expect(listed[0]).not.toHaveProperty("lines");
    expect(listed[0]).not.toHaveProperty("createdBy");
    expect(year).not.toHaveProperty("periodNumber");
    expect(year.lines[0]?.variance).toBe(-50_000n);
    expect(period.periodNumber).toBe(1);
    expect(t.calls.slice(0, 2)).toEqual([
      [
        "save_accounting_budget",
        {
          tenant: "org-1",
          name: "Plan 2026",
          fiscal_year: 2026,
          status: null,
          lines: [
            {
              accountCode: "8000",
              periodNumber: 1,
              amount: "300000",
              dimensions: { department: "sales" },
            },
            { accountId: "a1", periodNumber: 2, amount: "0" },
          ],
          budget_id: null,
        },
      ],
      [
        "save_accounting_budget",
        {
          tenant: "org-1",
          name: "Plan 2026",
          fiscal_year: 2026,
          status: "approved",
          lines: null,
          budget_id: "b1",
        },
      ],
    ]);
    expect(t.calls.slice(5)).toEqual([
      ["list_accounting_budgets", { tenant: "org-1", fiscal_year: null }],
      ["accounting_budget_vs_actual", { budget_id: "b1", period_number: null }],
      ["accounting_budget_vs_actual", { budget_id: "b1", period_number: 1 }],
    ]);
  });

  it("checks a tax report format's API version", async () => {
    const format: TaxReportFormat = {
      apiVersion: 1,
      name: "csv",
      render: (report) =>
        AsyncResult.ok({
          contentType: "text/csv",
          filename: `${report.organizationId}.csv`,
          body: report.boxes
            .map((box) => `${box.box},${String(box.tax)}`)
            .join("\n"),
        }),
    };

    expect(taxReportFormatOf(format)).toBe(format);

    const books = createAccounting({
      transport: fieldsTransport({ accounting_tax_report: () => TAX_REPORT }),
    });

    const report = await books
      .taxReport(
        "org-1",
        Temporal.PlainDate.from("2026-01-01"),
        Temporal.PlainDate.from("2026-03-31"),
      )
      .orThrow();

    const file = await taxReportFormatOf(format).render(report).orThrow();

    expect(file.body).toBe("1a,2100");
    expect(() =>
      taxReportFormatOf({
        ...format,
        // SAFETY: a format built for a later API version.
        apiVersion: 2 as unknown as 1,
      }),
    ).toThrow("targets tax report format API 2");
  });
});
