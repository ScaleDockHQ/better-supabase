import { Temporal } from "temporal-polyfill";
import { describe, expect, it } from "vitest";

import { createExpenses } from "../../../src/blocks/expenses/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const CATEGORY_ID = "00000000-0000-4000-8000-000000000001";

const LINE = {
  id: "line-1",
  reportId: "rep-1",
  categoryId: CATEGORY_ID,
  spentOn: "2026-10-20",
  description: "Train",
  amount: "4200",
  currency: "EUR",
  receipts: 0,
  createdAt: AT,
  updatedAt: AT,
};

const REPORT = {
  id: "rep-1",
  organizationId: "org-1",
  userId: "u1",
  title: "October trip",
  status: "draft",
  total: "0",
  currency: "EUR",
  lines: null,
  createdAt: AT,
  updatedAt: AT,
};

const lines = [1, 2].map((day) => ({
  categoryId: CATEGORY_ID,
  spentOn: Temporal.PlainDate.from({ year: 2026, month: 10, day }),
  amount: money(4200, "EUR"),
  description: `Day ${String(day)}`,
}));

function setup() {
  const t = fieldsTransport({
    create_expense_report: () => REPORT,
    add_expense_line: () => LINE,
    submit_expense_report: () => ({ ...REPORT, status: "submitted" }),
    get_expense_report: () => REPORT,
  });

  return { t, expenses: createExpenses({ transport: t, tenant: "org-1" }) };
}

describe("expenses helpers", () => {
  it("file creates the report, adds every line and submits it", async () => {
    const { t, expenses } = setup();

    const report = await expenses
      .file({ title: "October trip", currency: "EUR", lines })
      .orThrow();

    expect(report.status).toBe("submitted");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "create_expense_report",
      "add_expense_line",
      "add_expense_line",
      "submit_expense_report",
    ]);
  });

  it("file leaves the draft when submit is false", async () => {
    const { t, expenses } = setup();

    const report = await expenses
      .file({ title: "October trip", currency: "EUR", lines, submit: false })
      .orThrow();

    expect(report.status).toBe("draft");
    expect(t.calls.at(-1)?.[0]).toBe("get_expense_report");
  });

  it("file stops at the first failing line", async () => {
    const t = fieldsTransport({ create_expense_report: () => REPORT });

    const expenses = createExpenses({ transport: t, tenant: "org-1" });
    const report = await expenses.file({ title: "x", currency: "EUR", lines });

    expect(report.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "create_expense_report",
      "add_expense_line",
    ]);
  });
});
