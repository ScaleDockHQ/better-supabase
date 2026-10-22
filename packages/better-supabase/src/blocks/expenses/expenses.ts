import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
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

export interface ExpensesOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Expenses>>;
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

export interface ExpenseReport {
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
}

export interface ExpenseReportInput {
  readonly title: string;
  /** Three-letter code; every line is in it. */
  readonly currency: string;
  readonly note?: string;
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

export interface ReimbursementInput {
  readonly paidAt?: Temporal.Instant;
  readonly reference?: string;
}

export interface Expenses {
  /** Creates or updates the category with this key. Needs `expenses.manage`. */
  saveCategory(input: ExpenseCategoryInput): AsyncResult<ExpenseCategory>;
  archiveCategory(categoryId: string): AsyncResult<ExpenseCategory>;
  categories(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly ExpenseCategory[]>;
  /** A draft report of the caller. Needs `expenses.submit`. */
  create(input: ExpenseReportInput): AsyncResult<ExpenseReport>;
  addLine(reportId: string, line: ExpenseLineInput): AsyncResult<ExpenseLine>;
  updateLine(
    lineId: string,
    update: ExpenseLineUpdate,
  ): AsyncResult<ExpenseLine>;
  removeLine(lineId: string): AsyncResult<ExpenseReport>;
  /** The spend policy findings `submit` would refuse. */
  check(reportId: string): AsyncResult<readonly ExpensePolicyViolation[]>;
  /**
   * Opens an approval for a draft or rejected report. Fails with
   * `EXPENSE_POLICY_VIOLATION` while the report breaks the spend policy.
   */
  submit(reportId: string): AsyncResult<ExpenseReport>;
  /**
   * Pays an approved report out of the member's payable. Needs
   * `expenses.manage`.
   */
  reimburse(
    reportId: string,
    input?: ReimbursementInput,
  ): AsyncResult<ExpenseReport>;
  cancel(reportId: string): AsyncResult<ExpenseReport>;
  get(reportId: string): AsyncResult<ExpenseReport>;
  list(
    options?: ExpenseReportListOptions,
  ): AsyncResult<readonly ExpenseReport[]>;
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
export function createExpenses(options: ExpensesOptions): Expenses {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const report =
    (fn: string) =>
    (value: unknown): ExpenseReport =>
      reportOf(value, fn);

  const line =
    (fn: string) =>
    (value: unknown): ExpenseLine =>
      lineOf(value, fn);

  const category =
    (fn: string) =>
    (value: unknown): ExpenseCategory =>
      categoryOf(value, fn);

  const client: Expenses = {
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
      tenant().andThen((organizationId) =>
        call(
          "create_expense_report",
          {
            tenant: organizationId,
            title: input.title,
            currency: input.currency,
            note: input.note ?? null,
          },
          report("create_expense_report"),
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
      ),
    check: (reportId) =>
      call("check_expense_report", { report_id: reportId }, (value) =>
        recordsOf(value, "check_expense_report").map(violationOf),
      ),
    submit: (reportId) =>
      call(
        "submit_expense_report",
        { report_id: reportId },
        report("submit_expense_report"),
      ),
    reimburse: (reportId, input = {}) =>
      call(
        "reimburse_expense_report",
        {
          report_id: reportId,
          paid_at: instantArg(input.paidAt) ?? null,
          reference: input.reference ?? null,
        },
        report("reimburse_expense_report"),
      ),
    cancel: (reportId) =>
      call(
        "cancel_expense_report",
        { report_id: reportId },
        report("cancel_expense_report"),
      ),
    get: (reportId) =>
      call(
        "get_expense_report",
        { report_id: reportId },
        report("get_expense_report"),
      ),
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
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "expenses",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
