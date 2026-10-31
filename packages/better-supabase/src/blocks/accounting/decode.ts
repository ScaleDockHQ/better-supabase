import type { Money } from "../../commerce/money.ts";
import type {
  AccountingAccount,
  AccountingDimension,
  AccountingEntry,
  AccountingEntryStatus,
  AccountingFxRateInput,
  AccountingJournal,
  AccountingLine,
  AccountingLineInput,
  AccountingPeriod,
  AccountingPeriodStatus,
  AccountingSettings,
  AccountRole,
  AccountType,
  BalanceSheet,
  FiscalYearClose,
  GeneralLedger,
  JournalType,
  ProfitAndLoss,
  ReportLine,
  TaxCodeKind,
  TrialBalance,
} from "./accounting.ts";

import { bigintOf } from "../../core/block-helpers.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export const ACCOUNT_TYPES: readonly AccountType[] = [
  "asset",
  "liability",
  "equity",
  "income",
  "expense",
];

const ACCOUNT_ROLES: readonly AccountRole[] = [
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
];

const JOURNAL_TYPES: readonly JournalType[] = [
  "sales",
  "purchase",
  "bank",
  "cash",
  "general",
];

const PERIOD_STATUSES: readonly AccountingPeriodStatus[] = ["open", "closed"];

const ENTRY_STATUSES: readonly AccountingEntryStatus[] = [
  "draft",
  "posted",
  "reversed",
];

export const TAX_KINDS: readonly TaxCodeKind[] = ["sales", "purchase"];

export function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

export const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

export const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

export const decimalOf = (value: unknown): string =>
  typeof value === "number" ? String(value) : textOf(value);

const optionalDecimal = (value: unknown): string | undefined =>
  value === null || value === undefined ? undefined : decimalOf(value);

export const textRecord = (value: unknown): Readonly<Record<string, string>> =>
  isRecord(value)
    ? Object.fromEntries(
        Object.entries(value).flatMap(([key, item]) =>
          typeof item === "string" ? [[key, item]] : [],
        ),
      )
    : {};

const amountArg = (value: bigint | Money | undefined): string | undefined =>
  value === undefined
    ? undefined
    : (typeof value === "bigint" ? value : value.amount).toString();

export function settingsOf(value: unknown, fn: string): AccountingSettings {
  const row = recordOf(value, fn);

  return {
    organizationId: textOf(row["organizationId"]),
    functionalCurrency: textOf(row["functionalCurrency"]),
    fiscalYearStartMonth: numberOf(row["fiscalYearStartMonth"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("lockDate", optionalDate(row["lockDate"])),
  };
}

export function accountOf(value: unknown, fn: string): AccountingAccount {
  const row = recordOf(value, fn);
  const roles = Array.isArray(row["roles"]) ? row["roles"] : [];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    type: enumOrThrow(row["type"], ACCOUNT_TYPES, "account type"),
    reconcilable: row["reconcilable"] === true,
    roles: roles.map((role) =>
      enumOrThrow(role, ACCOUNT_ROLES, "account role"),
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("subtype", optionalText(row["subtype"])),
    ...optional("parentId", optionalText(row["parentId"])),
    ...optional("currency", optionalText(row["currency"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

export function journalOf(value: unknown, fn: string): AccountingJournal {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    type: enumOrThrow(row["type"], JOURNAL_TYPES, "journal type"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("defaultAccountId", optionalText(row["defaultAccountId"])),
    ...optional("currency", optionalText(row["currency"])),
  };
}

export function periodOf(value: unknown, fn: string): AccountingPeriod {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    fiscalYear: numberOf(row["fiscalYear"]),
    number: numberOf(row["number"]),
    startsOn: dateOf(row["startsOn"]),
    endsOn: dateOf(row["endsOn"]),
    status: enumOrThrow(row["status"], PERIOD_STATUSES, "period status"),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("closedBy", optionalText(row["closedBy"])),
  };
}

export function dimensionOf(value: unknown, fn: string): AccountingDimension {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    values: recordsOf(row["values"] ?? [], fn).map((item) => ({
      id: textOf(item["id"]),
      code: textOf(item["code"]),
      name: textOf(item["name"]),
      ...optional("archivedAt", optionalInstant(item["archivedAt"])),
    })),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function lineOf(row: Readonly<Record<string, unknown>>): AccountingLine {
  return {
    id: textOf(row["id"]),
    accountId: textOf(row["accountId"]),
    accountCode: textOf(row["accountCode"]),
    accountName: textOf(row["accountName"]),
    debit: bigintOf(row["debit"], "debit"),
    credit: bigintOf(row["credit"], "credit"),
    currency: textOf(row["currency"]),
    amountCurrency: bigintOf(row["amountCurrency"], "amountCurrency"),
    dimensions: textRecord(row["dimensions"]),
    ...optional("fxRate", optionalDecimal(row["fxRate"])),
    ...optional("taxCodeId", optionalText(row["taxCodeId"])),
    ...optional("partyId", optionalText(row["partyId"])),
    ...optional("description", optionalText(row["description"])),
  };
}

export function entryOf(value: unknown, fn: string): AccountingEntry {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    journalId: textOf(row["journalId"]),
    entryDate: dateOf(row["entryDate"]),
    status: enumOrThrow(row["status"], ENTRY_STATUSES, "entry status"),
    total: bigintOf(row["total"], "total"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("number", optionalText(row["number"])),
    ...optional("fiscalYear", optionalNumber(row["fiscalYear"])),
    ...optional("periodId", optionalText(row["periodId"])),
    ...optional("reference", optionalText(row["reference"])),
    ...optional("sourceType", optionalText(row["sourceType"])),
    ...optional("sourceId", optionalText(row["sourceId"])),
    ...optional("reversesId", optionalText(row["reversesId"])),
    ...optional("memo", optionalText(row["memo"])),
    ...optional(
      "lines",
      Array.isArray(row["lines"])
        ? recordsOf(row["lines"], fn).map(lineOf)
        : undefined,
    ),
    ...optional("postedAt", optionalInstant(row["postedAt"])),
    ...optional("postedBy", optionalText(row["postedBy"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function reportLineOf(row: Readonly<Record<string, unknown>>): ReportLine {
  return {
    accountId: textOf(row["accountId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    type: enumOrThrow(row["type"], ACCOUNT_TYPES, "account type"),
    amount: bigintOf(row["amount"], "amount"),
    ...optional("subtype", optionalText(row["subtype"])),
  };
}

export function trialBalanceOf(value: unknown, fn: string): TrialBalance {
  const row = recordOf(value, fn);
  const totals = recordOf(row["totals"], fn);

  return {
    accounts: recordsOf(row["accounts"] ?? [], fn).map((item) => ({
      accountId: textOf(item["accountId"]),
      code: textOf(item["code"]),
      name: textOf(item["name"]),
      type: enumOrThrow(item["type"], ACCOUNT_TYPES, "account type"),
      opening: bigintOf(item["opening"], "opening"),
      debit: bigintOf(item["debit"], "debit"),
      credit: bigintOf(item["credit"], "credit"),
      closing: bigintOf(item["closing"], "closing"),
    })),
    totals: {
      opening: bigintOf(totals["opening"], "opening"),
      debit: bigintOf(totals["debit"], "debit"),
      credit: bigintOf(totals["credit"], "credit"),
      closing: bigintOf(totals["closing"], "closing"),
    },
  };
}

export function profitAndLossOf(value: unknown, fn: string): ProfitAndLoss {
  const row = recordOf(value, fn);

  return {
    income: recordsOf(row["income"] ?? [], fn).map(reportLineOf),
    expenses: recordsOf(row["expenses"] ?? [], fn).map(reportLineOf),
    totalIncome: bigintOf(row["totalIncome"], "totalIncome"),
    totalExpenses: bigintOf(row["totalExpenses"], "totalExpenses"),
    netIncome: bigintOf(row["netIncome"], "netIncome"),
  };
}

export function balanceSheetOf(value: unknown, fn: string): BalanceSheet {
  const row = recordOf(value, fn);

  return {
    asOf: dateOf(row["asOf"]),
    assets: recordsOf(row["assets"] ?? [], fn).map(reportLineOf),
    liabilities: recordsOf(row["liabilities"] ?? [], fn).map(reportLineOf),
    equity: recordsOf(row["equity"] ?? [], fn).map(reportLineOf),
    currentEarnings: bigintOf(row["currentEarnings"], "currentEarnings"),
    totalAssets: bigintOf(row["totalAssets"], "totalAssets"),
    totalLiabilities: bigintOf(row["totalLiabilities"], "totalLiabilities"),
    totalEquity: bigintOf(row["totalEquity"], "totalEquity"),
    balanced: row["balanced"] === true,
  };
}

export function generalLedgerOf(value: unknown, fn: string): GeneralLedger {
  const row = recordOf(value, fn);
  const account = recordOf(row["account"], fn);

  return {
    account: {
      id: textOf(account["id"]),
      code: textOf(account["code"]),
      name: textOf(account["name"]),
      type: enumOrThrow(account["type"], ACCOUNT_TYPES, "account type"),
    },
    opening: bigintOf(row["opening"], "opening"),
    lines: recordsOf(row["lines"] ?? [], fn).map((item) => ({
      entryId: textOf(item["entryId"]),
      number: textOf(item["number"]),
      entryDate: dateOf(item["entryDate"]),
      journalId: textOf(item["journalId"]),
      debit: bigintOf(item["debit"], "debit"),
      credit: bigintOf(item["credit"], "credit"),
      balance: bigintOf(item["balance"], "balance"),
      ...optional("description", optionalText(item["description"])),
      ...optional("partyId", optionalText(item["partyId"])),
    })),
    closing: bigintOf(row["closing"], "closing"),
  };
}

export function fxRateOf(value: unknown, fn: string): AccountingFxRateInput {
  const row = recordOf(value, fn);

  return {
    base: textOf(row["base"]),
    quote: textOf(row["quote"]),
    onDate: dateOf(row["onDate"]),
    rate: decimalOf(row["rate"]),
  };
}

export function fiscalYearCloseOf(value: unknown, fn: string): FiscalYearClose {
  const row = recordOf(value, fn);

  return {
    organizationId: textOf(row["organizationId"]),
    fiscalYear: numberOf(row["fiscalYear"]),
    ...optional("closingEntryId", optionalText(row["closingEntryId"])),
  };
}

export function rolesOf(
  value: unknown,
  fn: string,
): Readonly<Partial<Record<AccountRole, string>>> {
  const row = recordOf(value, fn);

  return Object.fromEntries(
    Object.entries(row).map(([role, account]) => [
      enumOrThrow(role, ACCOUNT_ROLES, "account role"),
      textOf(account),
    ]),
  );
}

export const lineArg = (line: AccountingLineInput): Record<string, unknown> => {
  const foreign = line.amountCurrency;

  return {
    ...optional("accountId", line.accountId),
    ...optional("accountCode", line.accountCode),
    ...optional("debit", amountArg(line.debit)),
    ...optional("credit", amountArg(line.credit)),
    ...optional(
      "currency",
      foreign?.currency ??
        (typeof line.debit === "object" ? line.debit.currency : undefined) ??
        (typeof line.credit === "object" ? line.credit.currency : undefined),
    ),
    ...optional("amountCurrency", amountArg(foreign)),
    ...optional("fxRate", line.fxRate),
    ...optional("taxCodeId", line.taxCodeId),
    ...optional("partyId", line.partyId),
    ...optional("dimensions", line.dimensions),
    ...optional("description", line.description),
  };
};

export const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

export const maybe =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): T | undefined =>
    value === null || value === undefined ? undefined : of(value, fn);
