import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createExpenses,
  expenseCategoryInputSchema,
  expenseLineInputSchema,
  expenseReportInputSchema,
  expensesBlock,
  expensesEvents,
} from "../../../src/blocks/expenses/index.ts";
import { money } from "../../../src/commerce/money.ts";

const AT = "2026-10-22T10:00:00Z";
const CATEGORY_ID = "00000000-0000-4000-8000-000000000001";

const CATEGORY = {
  id: CATEGORY_ID,
  organizationId: "org-1",
  key: "travel",
  name: "Travel",
  currency: "EUR",
  limitAmount: "50000",
  receiptOver: "2500",
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const LINE = {
  id: "line-1",
  reportId: "rep-1",
  categoryId: CATEGORY_ID,
  spentOn: "2026-10-20",
  description: "Train",
  merchant: "NS",
  amount: "4200",
  currency: "EUR",
  receipts: 1,
  createdAt: AT,
  updatedAt: AT,
};

const REPORT = {
  id: "rep-1",
  organizationId: "org-1",
  userId: "u1",
  title: "October trip",
  note: "Client visit",
  status: "reimbursed",
  total: "4200",
  currency: "EUR",
  lines: [LINE],
  approvalId: "ap-1",
  submittedAt: AT,
  approvedAt: AT,
  approvalTransactionId: "t1",
  reimbursedAt: AT,
  reimbursementTransactionId: "t2",
  cancelledAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const DRAFT = {
  ...REPORT,
  status: "draft",
  total: "0",
  note: null,
  lines: null,
  approvalId: null,
  submittedAt: null,
  approvedAt: null,
  approvalTransactionId: null,
  reimbursedAt: null,
  reimbursementTransactionId: null,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createExpenses", () => {
  it("saves, archives and lists categories with their policy", async () => {
    const plain = {
      ...CATEGORY,
      currency: null,
      limitAmount: null,
      receiptOver: null,
      archivedAt: AT,
    };

    const fake = fakeTransport({
      save_expense_category: CATEGORY,
      archive_expense_category: plain,
      list_expense_categories: [CATEGORY, plain],
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const saved = await expenses
      .saveCategory({
        key: "travel",
        name: "Travel",
        limit: money(50_000n, "EUR"),
        receiptOver: money(2500n, "EUR"),
      })
      .orThrow();

    await expenses
      .saveCategory({
        key: "meals",
        name: "Meals",
        receiptOver: money(1000n, "EUR"),
      })
      .orThrow();
    await expenses.saveCategory({ key: "misc", name: "Misc" }).orThrow();

    const archived = await expenses.archiveCategory(CATEGORY_ID).orThrow();

    const listed = await expenses
      .categories({ includeArchived: true })
      .orThrow();

    await expenses.categories().orThrow();

    expect(saved).toMatchObject({
      key: "travel",
      limit: money(50_000n, "EUR"),
      receiptOver: money(2500n, "EUR"),
    });
    expect(saved).not.toHaveProperty("archivedAt");
    expect(archived).not.toHaveProperty("limit");
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(listed).toHaveLength(2);
    expect(fake.calls).toEqual([
      [
        "save_expense_category",
        {
          tenant: "org-1",
          key: "travel",
          name: "Travel",
          currency: "EUR",
          limit_amount: "50000",
          receipt_over: "2500",
        },
      ],
      [
        "save_expense_category",
        {
          tenant: "org-1",
          key: "meals",
          name: "Meals",
          currency: "EUR",
          limit_amount: null,
          receipt_over: "1000",
        },
      ],
      [
        "save_expense_category",
        {
          tenant: "org-1",
          key: "misc",
          name: "Misc",
          currency: null,
          limit_amount: null,
          receipt_over: null,
        },
      ],
      ["archive_expense_category", { category_id: CATEGORY_ID }],
      ["list_expense_categories", { tenant: "org-1", include_archived: true }],
      ["list_expense_categories", { tenant: "org-1", include_archived: false }],
    ]);
  });

  it("refuses a limit and a threshold in different currencies", async () => {
    const fake = fakeTransport({});

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const result = await expenses.saveCategory({
      key: "travel",
      name: "Travel",
      limit: money(1n, "EUR"),
      receiptOver: money(1n, "USD"),
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EXPENSE_CATEGORY_INVALID",
    );
    expect(fake.calls).toEqual([]);
  });

  it("writes and reads a category's extra columns", async () => {
    const fake = fakeTransport({
      save_expense_category: { ...CATEGORY, fields: { gl_code: "4100" } },
    });

    const saved = await createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    })
      .saveCategory({
        key: "travel",
        name: "Travel",
        fields: { gl_code: "4100" },
      })
      .orThrow();

    expect(saved.fields).toEqual({ gl_code: "4100" });
    expect(fake.calls[0]?.[1]).toMatchObject({ fields: { gl_code: "4100" } });
  });

  it("drafts a report and edits its lines", async () => {
    const bare = { ...LINE, merchant: null, receipts: null };

    const fake = fakeTransport({
      create_expense_report: DRAFT,
      add_expense_line: LINE,
      update_expense_line: bare,
      remove_expense_line: DRAFT,
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const draft = await expenses
      .create({ title: "October trip", currency: "EUR" })
      .orThrow();

    await expenses
      .create({ title: "October trip", currency: "EUR", note: "Client visit" })
      .orThrow();

    const added = await expenses
      .addLine("rep-1", {
        categoryId: CATEGORY_ID,
        spentOn: Temporal.PlainDate.from("2026-10-20"),
        amount: money(4200n, "EUR"),
        description: "Train",
        merchant: "NS",
        dimensions: { project: "proj-1" },
      })
      .orThrow();

    await expenses
      .addLine("rep-1", {
        categoryId: CATEGORY_ID,
        spentOn: Temporal.PlainDate.from("2026-10-20"),
        amount: money(4200n, "EUR"),
        description: "Train",
      })
      .orThrow();

    const updated = await expenses
      .updateLine("line-1", {
        categoryId: CATEGORY_ID,
        spentOn: Temporal.PlainDate.from("2026-10-21"),
        amount: money(4300n, "EUR"),
        description: "Train back",
        merchant: "NS",
      })
      .orThrow();

    await expenses.updateLine("line-1", {}).orThrow();
    await expenses.removeLine("line-1").orThrow();

    expect(draft.lines).toEqual([]);
    expect(draft).not.toHaveProperty("note");
    expect(draft).not.toHaveProperty("approvalId");
    expect(added).toMatchObject({
      merchant: "NS",
      receipts: 1,
      amount: money(4200n, "EUR"),
    });
    expect(added.spentOn.toString()).toBe("2026-10-20");
    expect(updated.receipts).toBe(0);
    expect(updated).not.toHaveProperty("merchant");
    expect(fake.calls).toEqual([
      [
        "create_expense_report",
        { tenant: "org-1", title: "October trip", currency: "EUR", note: null },
      ],
      [
        "create_expense_report",
        {
          tenant: "org-1",
          title: "October trip",
          currency: "EUR",
          note: "Client visit",
        },
      ],
      [
        "add_expense_line",
        {
          report_id: "rep-1",
          category_id: CATEGORY_ID,
          spent_on: "2026-10-20",
          amount: "4200",
          description: "Train",
          merchant: "NS",
          dimensions: { project: "proj-1" },
          currency: "EUR",
        },
      ],
      [
        "add_expense_line",
        {
          report_id: "rep-1",
          category_id: CATEGORY_ID,
          spent_on: "2026-10-20",
          amount: "4200",
          description: "Train",
          merchant: null,
          dimensions: null,
          currency: "EUR",
        },
      ],
      [
        "update_expense_line",
        {
          line_id: "line-1",
          category_id: CATEGORY_ID,
          spent_on: "2026-10-21",
          amount: "4300",
          description: "Train back",
          merchant: "NS",
          dimensions: null,
          currency: "EUR",
        },
      ],
      [
        "update_expense_line",
        {
          line_id: "line-1",
          category_id: null,
          spent_on: null,
          amount: null,
          description: null,
          merchant: null,
          dimensions: null,
          currency: null,
        },
      ],
      ["remove_expense_line", { line_id: "line-1" }],
    ]);
  });

  it("checks the spend policy and returns every kind of finding", async () => {
    const fake = fakeTransport({
      check_expense_report: [
        {
          kind: "limit",
          categoryId: CATEGORY_ID,
          category: "Travel",
          limit: "50000",
          total: "60000",
          currency: "EUR",
        },
        {
          kind: "receipt",
          categoryId: CATEGORY_ID,
          category: "Travel",
          lineId: "line-1",
          receiptOver: "2500",
          amount: "4200",
          currency: "EUR",
        },
        { kind: "archived", categoryId: CATEGORY_ID, category: "Old" },
      ],
    });

    const expenses = createExpenses({ transport: fake.transport });

    const findings = await expenses.check("rep-1").orThrow();

    expect(findings).toEqual([
      {
        kind: "limit",
        categoryId: CATEGORY_ID,
        category: "Travel",
        limit: money(50_000n, "EUR"),
        total: money(60_000n, "EUR"),
      },
      {
        kind: "receipt",
        categoryId: CATEGORY_ID,
        category: "Travel",
        lineId: "line-1",
        receiptOver: money(2500n, "EUR"),
        amount: money(4200n, "EUR"),
      },
      { kind: "archived", categoryId: CATEGORY_ID, category: "Old" },
    ]);
    expect(fake.calls).toEqual([
      ["check_expense_report", { report_id: "rep-1" }],
    ]);
  });

  it("rejects a finding of an unknown kind", async () => {
    const expenses = createExpenses({
      transport: fakeTransport({
        check_expense_report: [
          { kind: "budget", categoryId: CATEGORY_ID, category: "Travel" },
        ],
      }).transport,
    });

    expect((await expenses.check("rep-1")).ok).toBe(false);
  });

  it("submits, reimburses, cancels, reads and lists reports", async () => {
    const fake = fakeTransport({
      submit_expense_report: REPORT,
      reimburse_expense_report: REPORT,
      cancel_expense_report: { ...DRAFT, status: "cancelled", cancelledAt: AT },
      get_expense_report: REPORT,
      list_expense_reports: [REPORT, DRAFT],
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    await expenses.submit("rep-1").orThrow();

    const paid = await expenses
      .reimburse("rep-1", {
        paidAt: Temporal.Instant.from(AT),
        reference: "sepa-1",
      })
      .orThrow();

    await expenses.reimburse("rep-1").orThrow();

    const cancelled = await expenses.cancel("rep-1").orThrow();
    await expenses.get("rep-1").orThrow();

    const listed = await expenses
      .list({ status: "approved", userId: "u1", everyone: true, pageSize: 5 })
      .orThrow();

    await expenses.list().orThrow();

    expect(paid).toMatchObject({
      status: "reimbursed",
      note: "Client visit",
      approvalId: "ap-1",
      approvalTransactionId: "t1",
      reimbursementTransactionId: "t2",
      total: money(4200n, "EUR"),
    });
    expect(paid.lines[0]?.amount).toEqual(money(4200n, "EUR"));
    expect(paid.submittedAt?.toString()).toBe(AT);
    expect(paid.approvedAt?.toString()).toBe(AT);
    expect(paid.reimbursedAt?.toString()).toBe(AT);
    expect(cancelled.cancelledAt?.toString()).toBe(AT);
    expect(listed).toHaveLength(2);
    expect(fake.calls).toEqual([
      ["submit_expense_report", { report_id: "rep-1" }],
      [
        "reimburse_expense_report",
        { report_id: "rep-1", paid_at: AT, reference: "sepa-1" },
      ],
      [
        "reimburse_expense_report",
        { report_id: "rep-1", paid_at: null, reference: null },
      ],
      ["cancel_expense_report", { report_id: "rep-1" }],
      ["get_expense_report", { report_id: "rep-1" }],
      [
        "list_expense_reports",
        {
          tenant: "org-1",
          user_id: "u1",
          status: "approved",
          everyone: true,
          page_size: 5,
        },
      ],
      [
        "list_expense_reports",
        {
          tenant: "org-1",
          user_id: null,
          status: null,
          everyone: false,
          page_size: null,
        },
      ],
    ]);
  });

  it("records, submits, decides, reimburses and lists single expenses", async () => {
    const EXPENSE = {
      id: "exp-1",
      organizationId: "org-1",
      userId: null,
      employeeId: "emp-1",
      categoryId: null,
      spentOn: "2026-10-20",
      description: "Train",
      merchant: "NS",
      amount: "4250",
      currency: "EUR",
      status: "reimbursed",
      submittedAt: AT,
      decidedBy: "u2",
      decidedAt: AT,
      decisionNote: null,
      reimbursedAt: AT,
      reimbursement: "SEPA-1",
      createdAt: AT,
      updatedAt: AT,
    };

    const fake = fakeTransport({
      create_expense: { ...EXPENSE, status: "draft" },
      update_expense: { ...EXPENSE, status: "draft" },
      submit_expense: { ...EXPENSE, status: "submitted" },
      decide_expense: { ...EXPENSE, status: "approved" },
      reimburse_expense: EXPENSE,
      get_expense: EXPENSE,
      list_expenses: [EXPENSE],
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const created = await expenses
      .createExpense({
        spentOn: Temporal.PlainDate.from("2026-10-20"),
        amount: money(4250n, "EUR"),
        description: "Train",
        employeeId: "emp-1",
      })
      .orThrow();

    expect(created).toMatchObject({ status: "draft", employeeId: "emp-1" });
    expect(created.userId).toBeUndefined();
    await expenses
      .updateExpense("exp-1", { amount: money(4500n, "EUR") })
      .orThrow();
    await expenses.submitExpense("exp-1").orThrow();
    await expenses.decideExpense("exp-1", { approved: true }).orThrow();

    const paid = await expenses
      .reimburseExpense("exp-1", { reference: "SEPA-1" })
      .orThrow();

    expect(paid.amount).toEqual(money(4250n, "EUR"));
    expect(paid.reimbursement).toBe("SEPA-1");
    expect((await expenses.getExpense("exp-1").orThrow()).status).toBe(
      "reimbursed",
    );
    expect(
      await expenses
        .listExpenses({ employeeId: "emp-1", status: "reimbursed" })
        .orThrow(),
    ).toHaveLength(1);
    expect(fake.calls).toEqual([
      [
        "create_expense",
        {
          tenant: "org-1",
          spent_on: "2026-10-20",
          amount: "4250",
          currency: "EUR",
          category_id: null,
          description: "Train",
          merchant: null,
          user_id: null,
          employee_id: "emp-1",
        },
      ],
      [
        "update_expense",
        {
          expense_id: "exp-1",
          spent_on: null,
          amount: "4500",
          currency: "EUR",
          category_id: null,
          description: null,
          merchant: null,
        },
      ],
      ["submit_expense", { expense_id: "exp-1" }],
      ["decide_expense", { expense_id: "exp-1", approved: true, note: null }],
      ["reimburse_expense", { expense_id: "exp-1", reference: "SEPA-1" }],
      ["get_expense", { expense_id: "exp-1" }],
      [
        "list_expenses",
        {
          tenant: "org-1",
          user_id: null,
          status: "reimbursed",
          everyone: false,
          page_size: null,
          employee_id: "emp-1",
        },
      ],
    ]);
  });

  it("clears columns, sets fields, records company expenses, withdraws and deletes", async () => {
    const EXPENSE = {
      id: "exp-2",
      organizationId: "org-1",
      userId: null,
      employeeId: null,
      categoryId: null,
      spentOn: "2026-10-20",
      description: null,
      merchant: null,
      amount: "9900",
      currency: "EUR",
      status: "draft",
      createdAt: AT,
      updatedAt: AT,
      fields: { project: "P1" },
    };

    const fake = fakeTransport({
      create_expense: EXPENSE,
      update_expense: EXPENSE,
      withdraw_expense: EXPENSE,
      delete_expense: true,
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const created = await expenses
      .createExpense({
        spentOn: Temporal.PlainDate.from("2026-10-20"),
        amount: money(9900n, "EUR"),
        company: true,
      })
      .orThrow();

    expect(created.employeeId).toBeUndefined();
    await expenses
      .updateExpense("exp-2", {
        merchant: null,
        categoryId: null,
        fields: { project: "P1" },
      })
      .orThrow();
    expect((await expenses.withdrawExpense("exp-2").orThrow()).status).toBe(
      "draft",
    );
    expect(await expenses.deleteExpense("exp-2").orThrow()).toBe(true);
    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "create_expense",
      "update_expense",
      "withdraw_expense",
      "delete_expense",
    ]);
    expect(fake.calls[0]?.[1]).toMatchObject({ company: true });
    expect(fake.calls[1]?.[1]).toMatchObject({
      clear: ["category", "merchant"],
      fields: { project: "P1" },
    });
  });

  it("fails without a tenant", async () => {
    const expenses = createExpenses({ transport: fakeTransport({}).transport });

    expect((await expenses.list()).ok).toBe(false);
  });

  it("runs hooks with the logger it gets", async () => {
    const seen: string[] = [];

    const expenses = createExpenses({
      transport: fakeTransport({ get_expense_report: REPORT }).transport,
      hooks: {
        get: {
          before: (_args, info) => {
            seen.push(info.method);
          },
        },
      },
      logger: console,
    });

    await expenses.get("rep-1").orThrow();

    expect(seen).toEqual(["get"]);
  });
});

describe("expenses block", () => {
  it("declares its module, events and schemas", () => {
    expect(expensesBlock.name).toBe("expenses");
    expect(expensesBlock.sql).toEqual(["expenses"]);
    expect(expensesEvents.types).toContain("expense_report.reimbursed");
  });

  it("validates the inputs", () => {
    expect(
      validate(expenseReportInputSchema, { title: "Trip", currency: "EUR" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(expenseReportInputSchema, { title: "Trip", currency: "EURO" })
        .issues,
    ).toBeDefined();
    expect(
      validate(expenseLineInputSchema, {
        categoryId: CATEGORY_ID,
        spentOn: Temporal.PlainDate.from("2026-10-20"),
        amount: { amount: 4200n, currency: "EUR" },
        description: "Train",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(expenseCategoryInputSchema, { key: "travel" }).issues,
    ).toBeDefined();
  });
});

describe("expense report fields", () => {
  const Fields = v.object({ project: v.pipe(v.string(), v.minLength(2)) });

  it("validates the fields of a create, sends them and parses every read", async () => {
    const fake = fakeTransport({
      create_expense_report: { ...DRAFT, fields: { project: "apollo" } },
      list_expense_reports: [{ ...REPORT, fields: { project: "apollo" } }],
      submit_expense_report: { ...REPORT, fields: { project: "a" } },
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
      fields: Fields,
    });

    const report = await expenses
      .create({ title: "Trip", currency: "EUR", fields: { project: "apollo" } })
      .orThrow();

    expect(report.fields.project).toBe("apollo");
    expect(fake.calls[0]?.[1]["fields"]).toEqual({ project: "apollo" });
    expect(
      await expenses.create({
        title: "Trip",
        currency: "EUR",
        fields: { project: "a" },
      }),
    ).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(fake.calls).toHaveLength(1);
    expect(
      (await expenses.list().orThrow()).map((row) => row.fields.project),
    ).toEqual(["apollo"]);
    expect(await expenses.submit("rep-1")).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });

  it("decides a report without the approvals block", async () => {
    const fake = fakeTransport({
      decide_expense_report: { ...REPORT, status: "rejected" },
    });

    const expenses = createExpenses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const decided = await expenses
      .decide("rep-1", { approved: false, note: "receipt missing" })
      .orThrow();

    expect(fake.calls[0]).toEqual([
      "decide_expense_report",
      { report_id: "rep-1", approved: false, note: "receipt missing" },
    ]);
    expect(decided.status).toBe("rejected");
  });
});
