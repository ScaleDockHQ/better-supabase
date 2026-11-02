import { Temporal } from "temporal-polyfill";
import { describe, expect, it } from "vitest";

import { createAccounting } from "../../../src/blocks/accounting/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";

const SETTINGS = (startMonth: number) => ({
  organizationId: "org-1",
  functionalCurrency: "EUR",
  fiscalYearStartMonth: startMonth,
  createdAt: AT,
  updatedAt: AT,
});

const PERIOD = {
  id: "p1",
  organizationId: "org-1",
  fiscalYear: 2026,
  number: 1,
  startsOn: "2026-01-01",
  endsOn: "2026-01-31",
  status: "open",
};

function setup(startMonth: number | null) {
  const t = fieldsTransport({
    setup_accounting: () => SETTINGS(1),
    open_fiscal_year: () => [PERIOD],
    get_accounting_settings: () =>
      startMonth === null ? null : SETTINGS(startMonth),
    accounting_profit_and_loss: () => ({
      income: [],
      expenses: [],
      totalIncome: "0",
      totalExpenses: "0",
      netIncome: "0",
    }),
  });

  return { t, books: createAccounting({ transport: t }) };
}

describe("accounting helpers", () => {
  it("initialize sets accounting up and opens the fiscal year", async () => {
    const { t, books } = setup(1);

    const done = await books
      .initialize({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    expect(done.periods).toHaveLength(1);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "setup_accounting",
      "open_fiscal_year",
    ]);
  });

  it("yearToDate reports from the start of the fiscal year", async () => {
    const { t, books } = setup(1);

    const done = await books
      .yearToDate({
        organizationId: "org-1",
        asOf: Temporal.PlainDate.from("2026-10-22"),
      })
      .orThrow();

    expect(done.since.toString()).toBe("2026-01-01");
    expect(t.calls.at(-1)?.[1]).toMatchObject({
      since: "2026-01-01",
      until: "2026-10-22",
    });
  });

  it("yearToDate starts in the previous year before the start month", async () => {
    const { books } = setup(7);

    const done = await books
      .yearToDate({
        organizationId: "org-1",
        asOf: Temporal.PlainDate.from("2026-03-05"),
      })
      .orThrow();

    expect(done.since.toString()).toBe("2025-07-01");
  });

  it("yearToDate fails when accounting isn't set up", async () => {
    const { books } = setup(null);
    const done = await books.yearToDate({ organizationId: "org-1" });

    expect(done.ok ? undefined : done.error).toMatchObject({
      hint: "ACCOUNTING_NOT_SET_UP",
    });
  });
});
