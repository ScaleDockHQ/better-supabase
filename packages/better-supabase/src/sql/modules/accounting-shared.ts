import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The account types, in the order reports list them. */
export const ACCOUNT_TYPES = [
  "asset",
  "liability",
  "equity",
  "income",
  "expense",
] as const;

/** The roles an account can play, each mapped to one account per organization. */
export const ACCOUNT_ROLES = [
  "receivable",
  "payable",
  "bank",
  "revenue",
  "cogs",
  "inventory",
  "work_in_progress",
  "tax_payable",
  "tax_receivable",
  "retained_earnings",
  "fx_gain",
  "fx_loss",
  "fixed_asset",
  "accumulated_depreciation",
  "depreciation_expense",
  "disposal_gain",
  "disposal_loss",
  "expense",
  "suspense",
] as const;

export const JOURNAL_TYPES = [
  "sales",
  "purchase",
  "bank",
  "cash",
  "general",
] as const;

/** The subtypes `save_accounting_account` accepts when the config names none. */
const DEFAULT_SUBTYPES: readonly string[] = [
  "bank",
  "cash",
  "receivable",
  "inventory",
  "current_asset",
  "fixed_asset",
  "payable",
  "tax",
  "current_liability",
  "long_term_liability",
  "equity",
  "revenue",
  "other_income",
  "cogs",
  "operating_expense",
  "other_expense",
];

interface ChartAccount {
  readonly code: string;
  readonly name: string;
  readonly type: (typeof ACCOUNT_TYPES)[number];
  readonly subtype: string;
  readonly reconcilable?: boolean;
  readonly role?: (typeof ACCOUNT_ROLES)[number];
}

/** The generic chart: every role has an account. */
export const GENERIC_CHART: readonly ChartAccount[] = [
  {
    code: "1000",
    name: "Bank",
    type: "asset",
    subtype: "bank",
    reconcilable: true,
    role: "bank",
  },
  { code: "1100", name: "Cash", type: "asset", subtype: "cash" },
  {
    code: "1200",
    name: "Accounts receivable",
    type: "asset",
    subtype: "receivable",
    reconcilable: true,
    role: "receivable",
  },
  {
    code: "1300",
    name: "Inventory",
    type: "asset",
    subtype: "inventory",
    role: "inventory",
  },
  {
    code: "1350",
    name: "Work in progress",
    type: "asset",
    subtype: "inventory",
    role: "work_in_progress",
  },
  {
    code: "1400",
    name: "Tax receivable",
    type: "asset",
    subtype: "current_asset",
    role: "tax_receivable",
  },
  {
    code: "1500",
    name: "Fixed assets",
    type: "asset",
    subtype: "fixed_asset",
    role: "fixed_asset",
  },
  {
    code: "1510",
    name: "Accumulated depreciation",
    type: "asset",
    subtype: "fixed_asset",
    role: "accumulated_depreciation",
  },
  {
    code: "1900",
    name: "Suspense",
    type: "asset",
    subtype: "current_asset",
    role: "suspense",
  },
  {
    code: "2000",
    name: "Accounts payable",
    type: "liability",
    subtype: "payable",
    reconcilable: true,
    role: "payable",
  },
  {
    code: "2100",
    name: "Tax payable",
    type: "liability",
    subtype: "tax",
    role: "tax_payable",
  },
  { code: "3000", name: "Share capital", type: "equity", subtype: "equity" },
  {
    code: "3900",
    name: "Retained earnings",
    type: "equity",
    subtype: "equity",
    role: "retained_earnings",
  },
  {
    code: "4000",
    name: "Revenue",
    type: "income",
    subtype: "revenue",
    role: "revenue",
  },
  {
    code: "4900",
    name: "Exchange gains",
    type: "income",
    subtype: "other_income",
    role: "fx_gain",
  },
  {
    code: "4910",
    name: "Gains on asset disposals",
    type: "income",
    subtype: "other_income",
    role: "disposal_gain",
  },
  {
    code: "5000",
    name: "Cost of goods sold",
    type: "expense",
    subtype: "cogs",
    role: "cogs",
  },
  {
    code: "6000",
    name: "Operating expenses",
    type: "expense",
    subtype: "operating_expense",
    role: "expense",
  },
  {
    code: "6800",
    name: "Depreciation",
    type: "expense",
    subtype: "operating_expense",
    role: "depreciation_expense",
  },
  {
    code: "6900",
    name: "Exchange losses",
    type: "expense",
    subtype: "other_expense",
    role: "fx_loss",
  },
  {
    code: "6910",
    name: "Losses on asset disposals",
    type: "expense",
    subtype: "other_expense",
    role: "disposal_loss",
  },
];

/**
 * The journals `setup_accounting` creates, with the account code a journal
 * defaults to.
 */
export const DEFAULT_JOURNALS: readonly {
  readonly code: string;
  readonly name: string;
  readonly type: (typeof JOURNAL_TYPES)[number];
  readonly account?: string;
}[] = [
  { code: "SAL", name: "Sales", type: "sales" },
  { code: "PUR", name: "Purchases", type: "purchase" },
  { code: "BNK", name: "Bank", type: "bank", account: "1000" },
  { code: "CSH", name: "Cash", type: "cash", account: "1100" },
  { code: "GEN", name: "General", type: "general" },
];

/** The extra column keys the entry reads return next to the extra columns. */
export const ENTRY_RESERVED = ["fields", "lines", "total"] as const;

/** `'a', 'b'` for an `in (...)` list. */
export const sqlList = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

/** The options the module reads, checked. */
export interface AccountingConfig {
  readonly chart: "generic" | "none";
  readonly functionalCurrency: string;
  readonly fiscalYearStartMonth: number;
  readonly subtypes: readonly string[];
}

export function accountingConfig(ctx: BlockSqlContext): AccountingConfig {
  const chart = ctx.text("chart", "generic");
  const functionalCurrency = ctx.text("functionalCurrency", "EUR");
  const fiscalYearStartMonth = ctx.number("fiscalYearStartMonth", 1);
  const subtypes = ctx.list("subtypes", DEFAULT_SUBTYPES);

  if (chart !== "generic" && chart !== "none") {
    throw new TypeError(
      `blocks.accounting.options.chart must be "generic" or "none", not "${chart}"`,
    );
  }

  if (!/^[A-Z]{3}$/.test(functionalCurrency)) {
    throw new TypeError(
      "blocks.accounting.options.functionalCurrency must be an ISO 4217 code such as EUR",
    );
  }

  if (
    !Number.isInteger(fiscalYearStartMonth) ||
    fiscalYearStartMonth < 1 ||
    fiscalYearStartMonth > 12
  ) {
    throw new TypeError(
      "blocks.accounting.options.fiscalYearStartMonth must be a month from 1 to 12",
    );
  }

  const invalid = subtypes.filter(
    (subtype) => !/^[a-z][a-z0-9_]{0,62}$/.test(subtype),
  );

  if (invalid.length > 0 || subtypes.length === 0) {
    throw new TypeError(
      "blocks.accounting.options.subtypes must be lower-case identifiers",
    );
  }

  if (chart === "generic") {
    const missing = GENERIC_CHART.filter(
      (account) => !subtypes.includes(account.subtype),
    ).map((account) => account.subtype);

    if (missing.length > 0) {
      throw new TypeError(
        `blocks.accounting.options.subtypes must include the generic chart's ${[...new Set(missing)].join(", ")}, or set chart to "none"`,
      );
    }
  }

  return { chart, functionalCurrency, fiscalYearStartMonth, subtypes };
}

/** The permission checks and error helpers every accounting function shares. */
export interface AccountingSql {
  readonly read: string;
  readonly write: string;
  readonly post: string;
  readonly close: string;
  readonly manage: string;
  /** `(service or can(tenant, permission))`. */
  readonly allowed: (tenant: string, permission: string) => string;
  /** A `raise` with `<ENTITY>_FORBIDDEN`. */
  readonly forbidden: (entity: string, message: string) => string;
  readonly invalid: (entity: string, message: string) => string;
  readonly notFound: (entity: string, message: string) => string;
}

export function accountingSql(ctx: BlockSqlContext): AccountingSql {
  const permissions = moduleOperations("accounting");

  return {
    read: ctx.permission("read", permissions.read),
    write: ctx.permission("write", permissions.write),
    post: ctx.permission("post", permissions.post),
    close: ctx.permission("close", permissions.close),
    manage: ctx.permission("manage", permissions.manage),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`,
    forbidden: (entity, message) => fail(`${entity}_FORBIDDEN`, message),
    invalid: (entity, message) => fail(`${entity}_INVALID`, message, "22023"),
    notFound: (entity, message) =>
      fail(`${entity}_NOT_FOUND`, message, "P0002"),
  };
}
