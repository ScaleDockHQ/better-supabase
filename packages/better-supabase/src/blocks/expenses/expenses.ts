import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type ExpenseReportStatus =
  | "draft"
  | "submitted"
  | "approved"
  | "rejected"
  | "reimbursed"
  | "cancelled";

export interface ExpensesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the report's extra columns
   * (`blocks.expenses.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Expenses<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** A spend category with its policy. */
export interface ExpenseCategory {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  /** The most one report may spend in this category. */
  readonly limit?: Money;
  /** A line above this amount needs a receipt attached. */
  readonly receiptOver?: Money;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ExpenseCategoryInput {
  readonly key: string;
  readonly name: string;
  readonly limit?: Money;
  /** Needs the attachments block, where receipts live. */
  readonly receiptOver?: Money;
}

export interface ExpenseLine {
  readonly id: string;
  readonly reportId: string;
  readonly categoryId: string;
  readonly spentOn: Temporal.PlainDate;
  readonly description: string;
  readonly merchant?: string;
  readonly amount: Money;
  /** Receipts attached to the line (attachments with the line as subject). */
  readonly receipts: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ExpenseLineInput {
  readonly categoryId: string;
  readonly spentOn: Temporal.PlainDate;
  /** In the report's currency. */
  readonly amount: Money;
  readonly description: string;
  readonly merchant?: string;
}

export type ExpenseLineUpdate = Partial<ExpenseLineInput>;

/** A member's expense report. `F` types the extra columns. */
export interface ExpenseReport<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly title: string;
  readonly note?: string;
  readonly status: ExpenseReportStatus;
  readonly total: Money;
  readonly lines: readonly ExpenseLine[];
  readonly approvalId?: string;
  readonly submittedAt?: Temporal.Instant;
  readonly approvedAt?: Temporal.Instant;
  readonly approvalTransactionId?: string;
  readonly reimbursedAt?: Temporal.Instant;
  readonly reimbursementTransactionId?: string;
  readonly cancelledAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ExpenseReportInput<F extends object = Record<never, never>> {
  readonly title: string;
  /** Three-letter code; every line is in it. */
  readonly currency: string;
  readonly note?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/**
 * A spend policy finding: what `submit` refuses with
 * `EXPENSE_POLICY_VIOLATION`.
 */
export type ExpensePolicyViolation =
  | {
      readonly kind: "limit";
      readonly categoryId: string;
      readonly category: string;
      readonly limit: Money;
      readonly total: Money;
    }
  | {
      readonly kind: "receipt";
      readonly lineId: string;
      readonly categoryId: string;
      readonly category: string;
      readonly receiptOver: Money;
      readonly amount: Money;
    }
  | {
      readonly kind: "archived";
      readonly categoryId: string;
      readonly category: string;
    };

export interface ExpenseReportListOptions {
  readonly status?: ExpenseReportStatus;
  /** One member's reports. Needs `expenses.read` for another member. */
  readonly userId?: string;
  /** Every member's reports. Needs `expenses.read`. */
  readonly everyone?: boolean;
  readonly pageSize?: number;
}

export type ExpenseStatus =
  | "draft"
  | "submitted"
  | "approved"
  | "rejected"
  | "reimbursed";

export interface Expense<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly userId?: string;
  readonly employeeId?: string;
  readonly categoryId?: string;
  readonly spentOn: Temporal.PlainDate;
  readonly description?: string;
  readonly merchant?: string;
  readonly amount: Money;
  readonly status: ExpenseStatus;
  readonly submittedAt?: Temporal.Instant;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly decisionNote?: string;
  readonly reimbursedAt?: Temporal.Instant;
  readonly reimbursement?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

export interface ExpenseInput<F extends object = Record<never, never>> {
  readonly spentOn: Temporal.PlainDate;
  readonly amount: Money;
  readonly categoryId?: string;
  readonly description?: string;
  readonly merchant?: string;
  readonly userId?: string;
  readonly employeeId?: string;
  /**
   * An expense of the organization itself, without a member or employee. Needs
   * `options.companyExpenses` and `expenses.manage`.
   */
  readonly company?: boolean;
  readonly fields?: Partial<F>;
}

/** What it leaves out keeps its value; `null` clears the column. */
export interface ExpenseUpdate<F extends object = Record<never, never>> {
  readonly spentOn?: Temporal.PlainDate;
  readonly amount?: Money;
  readonly categoryId?: string | null;
  readonly description?: string | null;
  readonly merchant?: string | null;
  readonly fields?: Partial<F>;
}

export interface ExpenseListOptions {
  readonly status?: ExpenseStatus;
  readonly userId?: string;
  readonly employeeId?: string;
  readonly everyone?: boolean;
  readonly pageSize?: number;
}

export interface ReimbursementInput {
  readonly paidAt?: Temporal.Instant;
  readonly reference?: string;
}

export interface Expenses<F extends object = Record<never, never>> {
  /** Creates or updates the category with this key. Needs `expenses.manage`. */
  saveCategory(input: ExpenseCategoryInput): AsyncResult<ExpenseCategory>;
  archiveCategory(categoryId: string): AsyncResult<ExpenseCategory>;
  categories(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly ExpenseCategory[]>;
  /** A draft report of the caller. Needs `expenses.submit`. */
  create(input: ExpenseReportInput<F>): AsyncResult<ExpenseReport<F>>;
  addLine(reportId: string, line: ExpenseLineInput): AsyncResult<ExpenseLine>;
  updateLine(
    lineId: string,
    update: ExpenseLineUpdate,
  ): AsyncResult<ExpenseLine>;
  removeLine(lineId: string): AsyncResult<ExpenseReport<F>>;
  /** The spend policy findings `submit` would refuse. */
  check(reportId: string): AsyncResult<readonly ExpensePolicyViolation[]>;
  /**
   * Opens an approval for a draft or rejected report. Fails with
   * `EXPENSE_POLICY_VIOLATION` while the report breaks the spend policy.
   */
  submit(reportId: string): AsyncResult<ExpenseReport<F>>;
  /**
   * Pays an approved report out of the member's payable. Needs
   * `expenses.manage`.
   */
  reimburse(
    reportId: string,
    input?: ReimbursementInput,
  ): AsyncResult<ExpenseReport<F>>;
  cancel(reportId: string): AsyncResult<ExpenseReport<F>>;
  /**
   * Approves or rejects a submitted report when expenses run without the
   * approvals block (`options.approvals: false`). Needs `expenses.approve`, and
   * the owner can't decide their own.
   */
  decide(
    reportId: string,
    decision: { readonly approved: boolean; readonly note?: string },
  ): AsyncResult<ExpenseReport<F>>;
  get(reportId: string): AsyncResult<ExpenseReport<F>>;
  list(
    options?: ExpenseReportListOptions,
  ): AsyncResult<readonly ExpenseReport<F>[]>;
  createExpense(input: ExpenseInput<F>): AsyncResult<Expense<F>>;
  updateExpense(
    expenseId: string,
    update: ExpenseUpdate<F>,
  ): AsyncResult<Expense<F>>;
  submitExpense(expenseId: string): AsyncResult<Expense<F>>;
  /** Moves a submitted expense back to draft. */
  withdrawExpense(expenseId: string): AsyncResult<Expense<F>>;
  /** Deletes a draft expense. */
  deleteExpense(expenseId: string): AsyncResult<boolean>;
  decideExpense(
    expenseId: string,
    decision: { readonly approved: boolean; readonly note?: string },
  ): AsyncResult<Expense<F>>;
  reimburseExpense(
    expenseId: string,
    input?: { readonly reference?: string },
  ): AsyncResult<Expense<F>>;
  getExpense(expenseId: string): AsyncResult<Expense<F>>;
  listExpenses(
    options?: ExpenseListOptions,
  ): AsyncResult<readonly Expense<F>[]>;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function optionalInstant(
  value: unknown,
  field: string,
): Temporal.Instant | undefined {
  return value === null || value === undefined
    ? undefined
    : requiredInstant(value, field);
}

function optionalMoney(
  value: unknown,
  currency: unknown,
  field: string,
): Money | undefined {
  return value === null || value === undefined
    ? undefined
    : moneyOf(value, currency, field);
}

function categoryOf(value: unknown, fn: string): ExpenseCategory {
  const row = recordOf(value, fn);
  const currency = row["currency"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("limit", optionalMoney(row["limitAmount"], currency, "limit")),
    ...optional(
      "receiptOver",
      optionalMoney(row["receiptOver"], currency, "receiptOver"),
    ),
    ...optional("archivedAt", optionalInstant(row["archivedAt"], "archivedAt")),
  };
}

function lineOf(value: unknown, fn: string): ExpenseLine {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    reportId: textOf(row["reportId"]),
    categoryId: textOf(row["categoryId"]),
    spentOn: temporal().PlainDate.from(textOf(row["spentOn"])),
    description: textOf(row["description"]),
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    receipts: Number(row["receipts"] ?? 0),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("merchant", optionalText(row["merchant"])),
  };
}

function reportOf(value: unknown, fn: string): ExpenseReport {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    title: textOf(row["title"]),
    // SAFETY: the SQL derives status from these values only.
    status: textOf(row["status"]) as ExpenseReportStatus,
    total: moneyOf(row["total"], row["currency"], "total"),
    lines: recordsOf(row["lines"] ?? [], fn).map((line) => lineOf(line, fn)),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("note", optionalText(row["note"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional(
      "submittedAt",
      optionalInstant(row["submittedAt"], "submittedAt"),
    ),
    ...optional("approvedAt", optionalInstant(row["approvedAt"], "approvedAt")),
    ...optional(
      "approvalTransactionId",
      optionalText(row["approvalTransactionId"]),
    ),
    ...optional(
      "reimbursedAt",
      optionalInstant(row["reimbursedAt"], "reimbursedAt"),
    ),
    ...optional(
      "reimbursementTransactionId",
      optionalText(row["reimbursementTransactionId"]),
    ),
    ...optional(
      "cancelledAt",
      optionalInstant(row["cancelledAt"], "cancelledAt"),
    ),
  };
}

const EXPENSE_STATUSES: readonly ExpenseStatus[] = [
  "draft",
  "submitted",
  "approved",
  "rejected",
  "reimbursed",
];

function expenseOf(value: unknown, fn: string): Expense {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    spentOn: temporal().PlainDate.from(textOf(row["spentOn"])),
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    status: enumOrThrow(row["status"], EXPENSE_STATUSES, "expense status"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("userId", optionalText(row["userId"])),
    ...optional("employeeId", optionalText(row["employeeId"])),
    ...optional("categoryId", optionalText(row["categoryId"])),
    ...optional("description", optionalText(row["description"])),
    ...optional("merchant", optionalText(row["merchant"])),
    ...optional(
      "submittedAt",
      optionalInstant(row["submittedAt"], "submittedAt"),
    ),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"], "decidedAt")),
    ...optional("decisionNote", optionalText(row["decisionNote"])),
    ...optional(
      "reimbursedAt",
      optionalInstant(row["reimbursedAt"], "reimbursedAt"),
    ),
    ...optional("reimbursement", optionalText(row["reimbursement"])),
  };
}

function violationOf(value: unknown): ExpensePolicyViolation {
  const row = recordOf(value, "check_expense_report");
  const kind = textOf(row["kind"]);

  const base = {
    categoryId: textOf(row["categoryId"]),
    category: textOf(row["category"]),
  };

  switch (kind) {
    case "limit": {
      return {
        kind,
        ...base,
        limit: moneyOf(row["limit"], row["currency"], "limit"),
        total: moneyOf(row["total"], row["currency"], "total"),
      };
    }

    case "receipt": {
      return {
        kind,
        ...base,
        lineId: textOf(row["lineId"]),
        receiptOver: moneyOf(
          row["receiptOver"],
          row["currency"],
          "receiptOver",
        ),
        amount: moneyOf(row["amount"], row["currency"], "amount"),
      };
    }

    case "archived": {
      return { kind, ...base };
    }

    default: {
      throw new TypeError(`check_expense_report returned kind ${kind}`);
    }
  }
}

/** The `expenses` SQL module as typed calls. */
export function createExpenses<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ExpensesOptions<S>): Expenses<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const report =
    (fn: string) =>
    (value: unknown): ExpenseReport =>
      reportOf(value, fn);

  const expense =
    (fn: string) =>
    (value: unknown): Expense =>
      expenseOf(value, fn);

  const line =
    (fn: string) =>
    (value: unknown): ExpenseLine =>
      lineOf(value, fn);

  const category =
    (fn: string) =>
    (value: unknown): ExpenseCategory =>
      categoryOf(value, fn);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "expense report fields",
  );

  const client: Expenses<F> = {
    saveCategory: (input) => {
      const currency = input.limit?.currency ?? input.receiptOver?.currency;

      if (
        input.limit !== undefined &&
        input.receiptOver !== undefined &&
        input.limit.currency !== input.receiptOver.currency
      ) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            "the limit and the receipt threshold are in one currency",
            { hint: "EXPENSE_CATEGORY_INVALID" },
          ),
        );
      }

      return tenant().andThen((organizationId) =>
        call(
          "save_expense_category",
          {
            tenant: organizationId,
            key: input.key,
            name: input.name,
            currency: currency ?? null,
            limit_amount: input.limit ? amountText(input.limit) : null,
            receipt_over: input.receiptOver
              ? amountText(input.receiptOver)
              : null,
          },
          category("save_expense_category"),
        ),
      );
    },
    archiveCategory: (categoryId) =>
      call(
        "archive_expense_category",
        { category_id: categoryId },
        category("archive_expense_category"),
      ),
    categories: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_expense_categories",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_expense_categories").map(
              category("list_expense_categories"),
            ),
        ),
      ),
    create: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          tenant().andThen((organizationId) =>
            call(
              "create_expense_report",
              {
                tenant: organizationId,
                title: input.title,
                currency: input.currency,
                note: input.note ?? null,
                ...(checked === undefined ? {} : { fields: checked }),
              },
              report("create_expense_report"),
            ).andThen(fields.row),
          ),
        ),
    addLine: (reportId, input) =>
      call(
        "add_expense_line",
        {
          report_id: reportId,
          category_id: input.categoryId,
          spent_on: input.spentOn.toString(),
          amount: amountText(input.amount),
          description: input.description,
          merchant: input.merchant ?? null,
          currency: input.amount.currency,
        },
        line("add_expense_line"),
      ),
    updateLine: (lineId, update) =>
      call(
        "update_expense_line",
        {
          line_id: lineId,
          category_id: update.categoryId ?? null,
          spent_on: update.spentOn?.toString() ?? null,
          amount: update.amount ? amountText(update.amount) : null,
          description: update.description ?? null,
          merchant: update.merchant ?? null,
          currency: update.amount?.currency ?? null,
        },
        line("update_expense_line"),
      ),
    removeLine: (lineId) =>
      call(
        "remove_expense_line",
        { line_id: lineId },
        report("remove_expense_line"),
      ).andThen(fields.row),
    check: (reportId) =>
      call("check_expense_report", { report_id: reportId }, (value) =>
        recordsOf(value, "check_expense_report").map(violationOf),
      ),
    submit: (reportId) =>
      call(
        "submit_expense_report",
        { report_id: reportId },
        report("submit_expense_report"),
      ).andThen(fields.row),
    reimburse: (reportId, input = {}) =>
      call(
        "reimburse_expense_report",
        {
          report_id: reportId,
          paid_at: instantArg(input.paidAt) ?? null,
          reference: input.reference ?? null,
        },
        report("reimburse_expense_report"),
      ).andThen(fields.row),
    cancel: (reportId) =>
      call(
        "cancel_expense_report",
        { report_id: reportId },
        report("cancel_expense_report"),
      ).andThen(fields.row),
    decide: (reportId, decision) =>
      call(
        "decide_expense_report",
        {
          report_id: reportId,
          approved: decision.approved,
          note: decision.note ?? null,
        },
        report("decide_expense_report"),
      ).andThen(fields.row),
    get: (reportId) =>
      call(
        "get_expense_report",
        { report_id: reportId },
        report("get_expense_report"),
      ).andThen(fields.row),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_expense_reports",
          {
            tenant: organizationId,
            user_id: list.userId ?? null,
            status: list.status ?? null,
            everyone: list.everyone ?? false,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_expense_reports").map(
              report("list_expense_reports"),
            ),
        ).andThen(fields.rows),
      ),
    createExpense: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          tenant().andThen((organizationId) =>
            call(
              "create_expense",
              {
                tenant: organizationId,
                spent_on: input.spentOn.toString(),
                amount: amountText(input.amount),
                currency: input.amount.currency,
                category_id: input.categoryId ?? null,
                description: input.description ?? null,
                merchant: input.merchant ?? null,
                user_id: input.userId ?? null,
                ...optional("employee_id", input.employeeId),
                ...(input.company === true ? { company: true } : {}),
                ...(checked === undefined ? {} : { fields: checked }),
              },
              expense("create_expense"),
            ).andThen(fields.row),
          ),
        ),
    updateExpense: (expenseId, update) =>
      fields.args(update.fields).andThen((checked) => {
        const clear = (
          [
            ["category", update.categoryId],
            ["description", update.description],
            ["merchant", update.merchant],
          ] as const
        )
          .filter(([, value]) => value === null)
          .map(([name]) => name);

        return call(
          "update_expense",
          {
            expense_id: expenseId,
            spent_on: update.spentOn?.toString() ?? null,
            amount: update.amount ? amountText(update.amount) : null,
            currency: update.amount?.currency ?? null,
            category_id: update.categoryId ?? null,
            description: update.description ?? null,
            merchant: update.merchant ?? null,
            ...(clear.length === 0 ? {} : { clear }),
            ...(checked === undefined ? {} : { fields: checked }),
          },
          expense("update_expense"),
        ).andThen(fields.row);
      }),
    withdrawExpense: (expenseId) =>
      call(
        "withdraw_expense",
        { expense_id: expenseId },
        expense("withdraw_expense"),
      ).andThen(fields.row),
    deleteExpense: (expenseId) =>
      call(
        "delete_expense",
        { expense_id: expenseId },
        (value) => value === true,
      ),
    submitExpense: (expenseId) =>
      call(
        "submit_expense",
        { expense_id: expenseId },
        expense("submit_expense"),
      ).andThen(fields.row),
    decideExpense: (expenseId, decision) =>
      call(
        "decide_expense",
        {
          expense_id: expenseId,
          approved: decision.approved,
          note: decision.note ?? null,
        },
        expense("decide_expense"),
      ).andThen(fields.row),
    reimburseExpense: (expenseId, input = {}) =>
      call(
        "reimburse_expense",
        { expense_id: expenseId, reference: input.reference ?? null },
        expense("reimburse_expense"),
      ).andThen(fields.row),
    getExpense: (expenseId) =>
      call(
        "get_expense",
        { expense_id: expenseId },
        expense("get_expense"),
      ).andThen(fields.row),
    listExpenses: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_expenses",
          {
            tenant: organizationId,
            user_id: list.userId ?? null,
            status: list.status ?? null,
            everyone: list.everyone ?? false,
            page_size: list.pageSize ?? null,
            ...optional("employee_id", list.employeeId),
          },
          (value) =>
            recordsOf(value, "list_expenses").map(expense("list_expenses")),
        ).andThen(fields.rows),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "expenses",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
