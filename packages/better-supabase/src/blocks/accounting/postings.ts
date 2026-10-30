import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  AccountingEntry,
  AccountType,
  TaxCodeKind,
} from "./accounting.ts";

import { bigintOf } from "../../core/block-helpers.ts";
import {
  enumOrThrow,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import {
  ACCOUNT_TYPES,
  dateOf,
  entryOf,
  many,
  maybe,
  numberOf,
  optional,
  TAX_KINDS,
  textRecord,
} from "./decode.ts";

/** One tax code's base and tax over a report's dates. */
export interface TaxReportCode {
  readonly taxCodeId: string;
  readonly code: string;
  readonly name: string;
  readonly kind: TaxCodeKind;
  readonly rateBps: number;
  readonly reportBoxes: readonly string[];
  /** The net amount the tax was charged on, positive for sales and purchases. */
  readonly base: bigint;
  readonly tax: bigint;
}

/** The base and tax a return's box adds up from its tax codes. */
export interface TaxReportBox {
  readonly box: string;
  readonly base: bigint;
  readonly tax: bigint;
}

/** Posted tax per tax code and report box, in the functional currency. */
export interface TaxReport {
  readonly organizationId: string;
  readonly since: Temporal.PlainDate;
  readonly until: Temporal.PlainDate;
  readonly currency: string;
  readonly codes: readonly TaxReportCode[];
  readonly boxes: readonly TaxReportBox[];
  readonly salesTax: bigint;
  readonly purchaseTax: bigint;
  /** Sales tax less purchase tax: what is owed when positive. */
  readonly netTax: bigint;
}

/** A rendered tax return, such as a country's XML or CSV file. */
export interface TaxReportFile {
  readonly contentType: string;
  readonly filename: string;
  readonly body: string | Uint8Array;
}

/**
 * Renders a `TaxReport` in one filing format. Versioned: a breaking change
 * ships a new `apiVersion`. better-supabase bundles no format; a format package
 * maps the report boxes to its country's return.
 */
export interface TaxReportFormat {
  readonly apiVersion: 1;
  /** The format's name, such as `nl-btw-2026`. */
  readonly name: string;
  render(report: TaxReport): AsyncResult<TaxReportFile>;
}

/** Checks the format's `apiVersion` before rendering with it. */
export function taxReportFormatOf(format: TaxReportFormat): TaxReportFormat {
  const version: unknown = format.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `tax report format "${format.name}" targets tax report format API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the format for API 1.`,
    );
  }

  return format;
}

export type AccountingBudgetStatus = "draft" | "approved" | "archived";

const BUDGET_STATUSES: readonly AccountingBudgetStatus[] = [
  "draft",
  "approved",
  "archived",
];

export interface AccountingBudgetLine {
  readonly id: string;
  readonly accountId: string;
  readonly accountCode: string;
  /** The fiscal period, 1 to 12. */
  readonly periodNumber: number;
  readonly dimensions: Readonly<Record<string, string>>;
  /** Minor units of the functional currency, on the account's natural side. */
  readonly amount: bigint;
}

export interface AccountingBudget {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly fiscalYear: number;
  readonly status: AccountingBudgetStatus;
  /** The sum of the lines. */
  readonly total: bigint;
  /** On `budget` and `saveBudget`; `budgets` leaves them out. */
  readonly lines?: readonly AccountingBudgetLine[];
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AccountingBudgetLineInput {
  /** The account by id, or by `accountCode`. */
  readonly accountId?: string;
  readonly accountCode?: string;
  readonly periodNumber: number;
  readonly amount: bigint;
  readonly dimensions?: Readonly<Record<string, string>>;
}

export interface AccountingBudgetInput {
  readonly name: string;
  readonly fiscalYear: number;
  readonly status?: AccountingBudgetStatus;
  /** Replaces every line; leave it out to keep them. */
  readonly lines?: readonly AccountingBudgetLineInput[];
  /** Updates this budget instead of adding one. */
  readonly budgetId?: string;
}

export interface BudgetVsActualLine {
  readonly accountId: string;
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  readonly dimensions: Readonly<Record<string, string>>;
  readonly budget: bigint;
  readonly actual: bigint;
  /** Actual less budget. */
  readonly variance: bigint;
}

export interface BudgetVsActual {
  readonly budgetId: string;
  readonly name: string;
  readonly fiscalYear: number;
  /** Missing for the whole year. */
  readonly periodNumber?: number;
  readonly lines: readonly BudgetVsActualLine[];
  readonly budget: bigint;
  readonly actual: bigint;
}

/** The accounting client's calls for postings, the tax report and budgets. */
export interface AccountingPostings {
  /**
   * Books a document a block contributes (such as `invoice`) once; a second
   * call returns the same entry. With `autoPost` off the entry stays a draft.
   * Undefined when the block has nothing to book. Needs `accounting.post`.
   */
  postSource(
    sourceType: string,
    sourceId: string,
  ): AsyncResult<AccountingEntry | undefined>;
  /** Posted tax per tax code and report box between two dates. */
  taxReport(
    organizationId: string,
    since: Temporal.PlainDate,
    until: Temporal.PlainDate,
  ): AsyncResult<TaxReport>;
  /** Adds or updates a budget. Needs `accounting.write`. */
  saveBudget(
    organizationId: string,
    input: AccountingBudgetInput,
  ): AsyncResult<AccountingBudget>;
  budget(budgetId: string): AsyncResult<AccountingBudget | undefined>;
  budgets(
    organizationId: string,
    fiscalYear?: number,
  ): AsyncResult<readonly AccountingBudget[]>;
  /** Planned against posted amounts per account and dimensions. */
  budgetVsActual(
    budgetId: string,
    periodNumber?: number,
  ): AsyncResult<BudgetVsActual>;
}

const amount = (row: Readonly<Record<string, unknown>>, key: string): bigint =>
  bigintOf(row[key], key);

function taxReportOf(value: unknown, fn: string): TaxReport {
  const row = recordOf(value, fn);

  return {
    organizationId: textOf(row["organizationId"]),
    since: dateOf(row["since"]),
    until: dateOf(row["until"]),
    currency: textOf(row["currency"]),
    codes: recordsOf(row["codes"] ?? [], fn).map((item) => ({
      taxCodeId: textOf(item["taxCodeId"]),
      code: textOf(item["code"]),
      name: textOf(item["name"]),
      kind: enumOrThrow(item["kind"], TAX_KINDS, "tax code kind"),
      rateBps: numberOf(item["rateBps"]),
      reportBoxes: Array.isArray(item["reportBoxes"])
        ? item["reportBoxes"].map(textOf)
        : [],
      base: amount(item, "base"),
      tax: amount(item, "tax"),
    })),
    boxes: recordsOf(row["boxes"] ?? [], fn).map((item) => ({
      box: textOf(item["box"]),
      base: amount(item, "base"),
      tax: amount(item, "tax"),
    })),
    salesTax: amount(row, "salesTax"),
    purchaseTax: amount(row, "purchaseTax"),
    netTax: amount(row, "netTax"),
  };
}

function budgetOf(value: unknown, fn: string): AccountingBudget {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    fiscalYear: numberOf(row["fiscalYear"]),
    status: enumOrThrow(row["status"], BUDGET_STATUSES, "budget status"),
    total: amount(row, "total"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional(
      "lines",
      Array.isArray(row["lines"])
        ? recordsOf(row["lines"], fn).map((item) => ({
            id: textOf(item["id"]),
            accountId: textOf(item["accountId"]),
            accountCode: textOf(item["accountCode"]),
            periodNumber: numberOf(item["periodNumber"]),
            dimensions: textRecord(item["dimensions"]),
            amount: amount(item, "amount"),
          }))
        : undefined,
    ),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function budgetVsActualOf(value: unknown, fn: string): BudgetVsActual {
  const row = recordOf(value, fn);
  const period = row["periodNumber"];

  return {
    budgetId: textOf(row["budgetId"]),
    name: textOf(row["name"]),
    fiscalYear: numberOf(row["fiscalYear"]),
    lines: recordsOf(row["lines"] ?? [], fn).map((item) => ({
      accountId: textOf(item["accountId"]),
      code: textOf(item["code"]),
      name: textOf(item["name"]),
      type: enumOrThrow(item["type"], ACCOUNT_TYPES, "account type"),
      dimensions: textRecord(item["dimensions"]),
      budget: amount(item, "budget"),
      actual: amount(item, "actual"),
      variance: amount(item, "variance"),
    })),
    budget: amount(row, "budget"),
    actual: amount(row, "actual"),
    ...optional(
      "periodNumber",
      period === null || period === undefined ? undefined : numberOf(period),
    ),
  };
}

const lineArg = (
  line: AccountingBudgetLineInput,
): Readonly<Record<string, unknown>> => ({
  ...optional("accountId", line.accountId),
  ...optional("accountCode", line.accountCode),
  periodNumber: line.periodNumber,
  amount: line.amount.toString(),
  ...optional("dimensions", line.dimensions),
});

/**
 * The postings, tax report and budget calls over the accounting client's
 * `call`.
 */
export function accountingPostings(call: BlockCall): AccountingPostings {
  return {
    postSource: (sourceType, sourceId) =>
      call(
        "post_accounting_source",
        { source_type: sourceType, source_id: sourceId },
        maybe("post_accounting_source", entryOf),
      ),
    taxReport: (organizationId, since, until) =>
      call(
        "accounting_tax_report",
        {
          tenant: organizationId,
          since: since.toString(),
          until: until.toString(),
        },
        (value) => taxReportOf(value, "accounting_tax_report"),
      ),
    saveBudget: (organizationId, input) =>
      call(
        "save_accounting_budget",
        {
          tenant: organizationId,
          name: input.name,
          fiscal_year: input.fiscalYear,
          status: input.status ?? null,
          lines: input.lines?.map(lineArg) ?? null,
          budget_id: input.budgetId ?? null,
        },
        (value) => budgetOf(value, "save_accounting_budget"),
      ),
    budget: (budgetId) =>
      call(
        "get_accounting_budget",
        { budget_id: budgetId },
        maybe("get_accounting_budget", budgetOf),
      ),
    budgets: (organizationId, fiscalYear) =>
      call(
        "list_accounting_budgets",
        { tenant: organizationId, fiscal_year: fiscalYear ?? null },
        many("list_accounting_budgets", budgetOf),
      ),
    budgetVsActual: (budgetId, periodNumber) =>
      call(
        "accounting_budget_vs_actual",
        { budget_id: budgetId, period_number: periodNumber ?? null },
        (value) => budgetVsActualOf(value, "accounting_budget_vs_actual"),
      ),
  };
}
