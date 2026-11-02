import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  AccountingEntry,
  AccountingPeriod,
  AccountType,
  TrialBalance,
} from "./accounting.ts";

import { bigintOf } from "../../core/block-helpers.ts";
import {
  enumOrThrow,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import {
  ACCOUNT_TYPES,
  dateOf,
  entryOf,
  numberOf,
  optional,
  periodOf,
  trialBalanceOf,
} from "./decode.ts";

/** One opening balance: a signed amount, a debit balance positive. */
export interface OpeningBalance {
  readonly id: string;
  readonly organizationId: string;
  readonly fiscalYear: number;
  readonly accountId: string;
  /** The customer, supplier or employee behind a receivable or payable. */
  readonly partyId?: string;
  /** Minor units of the functional currency. */
  readonly amount: bigint;
  /** `imported` rows come from the old books, `carried` from the year close. */
  readonly source: "imported" | "carried";
}

export interface OpeningBalanceInput {
  /** The account's id, or `accountCode` instead. */
  readonly accountId?: string;
  readonly accountCode?: string;
  readonly partyId?: string;
  /** Signed minor units of the functional currency; a debit balance is positive. */
  readonly amount: bigint;
}

export interface OpeningBalances {
  readonly organizationId: string;
  readonly fiscalYear: number;
  /** Whether the year's opening entry is posted. */
  readonly posted: boolean;
  readonly balances: readonly OpeningBalance[];
  /** Zero when the balances add up. */
  readonly total: bigint;
}

/** One account on the column balance. */
export interface ColumnBalanceRow {
  readonly accountId: string;
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  readonly parentId?: string;
  readonly level: number;
  readonly openingDebit: bigint;
  readonly openingCredit: bigint;
  readonly debit: bigint;
  readonly credit: bigint;
  readonly closingDebit: bigint;
  readonly closingCredit: bigint;
}

export interface ColumnBalance {
  readonly accounts: readonly ColumnBalanceRow[];
  /** Each line counted once, whether or not the rows roll up. */
  readonly totals: Omit<
    ColumnBalanceRow,
    "accountId" | "code" | "name" | "type" | "parentId" | "level"
  >;
}

export interface JournalListingLine {
  readonly accountId: string;
  readonly accountCode: string;
  readonly accountName: string;
  readonly debit: bigint;
  readonly credit: bigint;
  readonly taxAmount: bigint;
  readonly partyId?: string;
  readonly description?: string;
}

export interface JournalListingEntry {
  readonly id: string;
  readonly number?: string;
  readonly entryDate: Temporal.PlainDate;
  readonly status: "posted" | "reversed";
  readonly reference?: string;
  readonly memo?: string;
  readonly lines: readonly JournalListingLine[];
}

export interface JournalListingJournal {
  readonly journalId: string;
  readonly code: string;
  readonly name: string;
  readonly type: string;
  readonly entries: readonly JournalListingEntry[];
  readonly totalDebit: bigint;
  readonly totalCredit: bigint;
}

export interface JournalListing {
  readonly journals: readonly JournalListingJournal[];
}

export interface ColumnBalanceOptions {
  readonly since?: Temporal.PlainDate;
  readonly until?: Temporal.PlainDate;
  readonly dimensions?: Readonly<Record<string, string>>;
  /** A parent account adds up the accounts below it. */
  readonly rollup?: boolean;
}

export interface JournalListingOptions {
  readonly since?: Temporal.PlainDate;
  readonly until?: Temporal.PlainDate;
  readonly journalId?: string;
}

/**
 * Period locks, opening balances and the ledger reports of the accounting
 * client.
 */
export interface AccountingLedger {
  /**
   * Locks a closed period: nothing posts into it, a ledger import included.
   * Needs `accounting.close`.
   */
  lockPeriod(periodId: string): AsyncResult<AccountingPeriod>;
  /** Puts a locked period back to closed. Needs `accounting.close` and a reason. */
  unlockPeriod(input: {
    periodId: string;
    reason: string;
  }): AsyncResult<AccountingPeriod>;
  /**
   * Saves a fiscal year's opening balances, each replacing the row of its
   * account and party. Needs `accounting.manage`.
   */
  saveOpeningBalances(input: {
    organizationId: string;
    fiscalYear: number;
    balances: readonly OpeningBalanceInput[];
  }): AsyncResult<readonly OpeningBalance[]>;
  /** The imported and carried balances of a fiscal year. */
  openingBalances(input: {
    organizationId: string;
    fiscalYear: number;
  }): AsyncResult<OpeningBalances>;
  /**
   * Posts the imported balances as one entry on the year's first day. They must
   * add up to zero; posting twice returns the same entry. Needs
   * `accounting.post`.
   */
  postOpeningBalances(
    input: { organizationId: string; fiscalYear: number } & {
      readonly journalId?: string;
    },
  ): AsyncResult<AccountingEntry>;
  /** The trial balance of one period. */
  periodTrialBalance(
    input: { periodId: string } & {
      readonly dimensions?: Readonly<Record<string, string>>;
    },
  ): AsyncResult<TrialBalance>;
  /**
   * Per account the opening, period and closing balance as debit and credit
   * columns.
   */
  columnBalance(
    input: { organizationId: string } & ColumnBalanceOptions,
  ): AsyncResult<ColumnBalance>;
  /** The posted entries with their lines, per journal. */
  journalListing(
    input: { organizationId: string } & JournalListingOptions,
  ): AsyncResult<JournalListing>;
}

const SOURCES = ["imported", "carried"] as const;

function openingOf(row: Readonly<Record<string, unknown>>): OpeningBalance {
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    fiscalYear: numberOf(row["fiscalYear"]),
    accountId: textOf(row["accountId"]),
    amount: bigintOf(row["amount"], "amount"),
    source: enumOrThrow(row["source"], SOURCES, "opening balance source"),
    ...optional("partyId", optionalText(row["partyId"])),
  };
}

function columnRowOf(row: Readonly<Record<string, unknown>>): ColumnBalanceRow {
  return {
    accountId: textOf(row["accountId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    type: enumOrThrow(row["type"], ACCOUNT_TYPES, "account type"),
    level: numberOf(row["level"]),
    openingDebit: bigintOf(row["openingDebit"], "openingDebit"),
    openingCredit: bigintOf(row["openingCredit"], "openingCredit"),
    debit: bigintOf(row["debit"], "debit"),
    credit: bigintOf(row["credit"], "credit"),
    closingDebit: bigintOf(row["closingDebit"], "closingDebit"),
    closingCredit: bigintOf(row["closingCredit"], "closingCredit"),
    ...optional("parentId", optionalText(row["parentId"])),
  };
}

function columnBalanceOf(value: unknown, fn: string): ColumnBalance {
  const row = recordOf(value, fn);
  const totals = recordOf(row["totals"], fn);

  return {
    accounts: recordsOf(row["accounts"] ?? [], fn).map(columnRowOf),
    totals: {
      openingDebit: bigintOf(totals["openingDebit"], "openingDebit"),
      openingCredit: bigintOf(totals["openingCredit"], "openingCredit"),
      debit: bigintOf(totals["debit"], "debit"),
      credit: bigintOf(totals["credit"], "credit"),
      closingDebit: bigintOf(totals["closingDebit"], "closingDebit"),
      closingCredit: bigintOf(totals["closingCredit"], "closingCredit"),
    },
  };
}

const LISTED = ["posted", "reversed"] as const;

function listingLineOf(
  row: Readonly<Record<string, unknown>>,
): JournalListingLine {
  return {
    accountId: textOf(row["accountId"]),
    accountCode: textOf(row["accountCode"]),
    accountName: textOf(row["accountName"]),
    debit: bigintOf(row["debit"], "debit"),
    credit: bigintOf(row["credit"], "credit"),
    taxAmount: bigintOf(row["taxAmount"], "taxAmount"),
    ...optional("partyId", optionalText(row["partyId"])),
    ...optional("description", optionalText(row["description"])),
  };
}

function journalListingOf(value: unknown, fn: string): JournalListing {
  const row = recordOf(value, fn);

  return {
    journals: recordsOf(row["journals"] ?? [], fn).map((journal) => ({
      journalId: textOf(journal["journalId"]),
      code: textOf(journal["code"]),
      name: textOf(journal["name"]),
      type: textOf(journal["type"]),
      totalDebit: bigintOf(journal["totalDebit"], "totalDebit"),
      totalCredit: bigintOf(journal["totalCredit"], "totalCredit"),
      entries: recordsOf(journal["entries"] ?? [], fn).map((entry) => ({
        id: textOf(entry["id"]),
        entryDate: dateOf(entry["entryDate"]),
        status: enumOrThrow(entry["status"], LISTED, "entry status"),
        lines: recordsOf(entry["lines"] ?? [], fn).map(listingLineOf),
        ...optional("number", optionalText(entry["number"])),
        ...optional("reference", optionalText(entry["reference"])),
        ...optional("memo", optionalText(entry["memo"])),
      })),
    })),
  };
}

const balanceArg = (input: OpeningBalanceInput): Record<string, unknown> => ({
  amount: input.amount.toString(),
  ...optional("accountId", input.accountId),
  ...optional("accountCode", input.accountCode),
  ...optional("partyId", input.partyId),
});

/**
 * The period lock, opening balance and ledger report calls over the accounting
 * client's `call`.
 */
export function accountingLedger(call: BlockCall): AccountingLedger {
  return {
    lockPeriod: (periodId) =>
      call("lock_accounting_period", { period_id: periodId }, (value) =>
        periodOf(value, "lock_accounting_period"),
      ),
    unlockPeriod: ({ periodId, reason }) =>
      call(
        "unlock_accounting_period",
        { period_id: periodId, reason },
        (value) => periodOf(value, "unlock_accounting_period"),
      ),
    saveOpeningBalances: ({ organizationId, fiscalYear, balances }) =>
      call(
        "save_accounting_opening_balances",
        {
          tenant: organizationId,
          fiscal_year: fiscalYear,
          balances: balances.map(balanceArg),
        },
        (value) =>
          recordsOf(
            recordOf(value, "save_accounting_opening_balances")["balances"] ??
              [],
            "save_accounting_opening_balances",
          ).map(openingOf),
      ),
    openingBalances: ({ organizationId, fiscalYear }) =>
      call(
        "list_accounting_opening_balances",
        { tenant: organizationId, fiscal_year: fiscalYear },
        (value) => {
          const row = recordOf(value, "list_accounting_opening_balances");

          return {
            organizationId: textOf(row["organizationId"]),
            fiscalYear: numberOf(row["fiscalYear"]),
            posted: row["posted"] === true,
            balances: recordsOf(
              row["balances"] ?? [],
              "list_accounting_opening_balances",
            ).map(openingOf),
            total: bigintOf(row["total"], "total"),
          };
        },
      ),
    postOpeningBalances: ({ organizationId, fiscalYear, ...options }) =>
      call(
        "post_accounting_opening_balances",
        {
          tenant: organizationId,
          fiscal_year: fiscalYear,
          journal_id: options.journalId ?? null,
        },
        (value) => entryOf(value, "post_accounting_opening_balances"),
      ),
    periodTrialBalance: ({ periodId, ...options }) =>
      call(
        "accounting_period_trial_balance",
        { period_id: periodId, dimensions: options.dimensions ?? {} },
        (value) => trialBalanceOf(value, "accounting_period_trial_balance"),
      ),
    columnBalance: ({ organizationId, ...options }) =>
      call(
        "accounting_column_balance",
        {
          tenant: organizationId,
          since: options.since?.toString() ?? null,
          until: options.until?.toString() ?? null,
          dimensions: options.dimensions ?? {},
          rollup: options.rollup ?? false,
        },
        (value) => columnBalanceOf(value, "accounting_column_balance"),
      ),
    journalListing: ({ organizationId, ...options }) =>
      call(
        "accounting_journal_listing",
        {
          tenant: organizationId,
          since: options.since?.toString() ?? null,
          until: options.until?.toString() ?? null,
          journal_id: options.journalId ?? null,
        },
        (value) => journalListingOf(value, "accounting_journal_listing"),
      ),
  };
}
