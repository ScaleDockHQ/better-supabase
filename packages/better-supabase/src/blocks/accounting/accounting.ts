import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { AccountingLedger } from "./ledger.ts";
import type { AccountingPostings } from "./postings.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { applyTemporal, blockCall, recordOf, textOf } from "../shared.ts";
import {
  accountOf,
  balanceSheetOf,
  decimalOf,
  dimensionOf,
  entryOf,
  fiscalYearCloseOf,
  fxRateOf,
  generalLedgerOf,
  journalOf,
  lineArg,
  many,
  maybe,
  periodOf,
  profitAndLossOf,
  rolesOf,
  settingsOf,
  trialBalanceOf,
} from "./decode.ts";
import { accountingLedger } from "./ledger.ts";
import {
  accountingAccountListSurface,
  accountingEntryListSurface,
} from "./lists.ts";
import { accountingPostings } from "./postings.ts";

export interface AccountingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the entry's extra columns (columns the app's schema
   * files add to the table), keyed by database name. It types and parses them
   * on reads, and validates them on `saveEntry`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Accounting<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type AccountType =
  | "asset"
  | "liability"
  | "equity"
  | "income"
  | "expense";

/** The roles an account can play; each maps to one account per organization. */
export type AccountRole =
  | "receivable"
  | "payable"
  | "bank"
  | "revenue"
  | "cogs"
  | "inventory"
  | "work_in_progress"
  | "tax_payable"
  | "tax_receivable"
  | "deferred_revenue"
  | "retained_earnings"
  | "fx_gain"
  | "fx_loss"
  | "fixed_asset"
  | "accumulated_depreciation"
  | "depreciation_expense"
  | "disposal_gain"
  | "disposal_loss"
  | "expense"
  | "suspense";

export type JournalType = "sales" | "purchase" | "bank" | "cash" | "general";

/** A locked period is closed and refuses every post, imports included. */
export type AccountingPeriodStatus = "open" | "closed" | "locked";

/** The side an account's balance normally sits on. */
export type AccountNormalSide = "debit" | "credit";

export type AccountingEntryStatus = "draft" | "posted" | "reversed";

/** An organization's accounting settings. */
export interface AccountingSetup {
  readonly organizationId: string;
  /** Every debit and credit is in minor units of this currency. */
  readonly functionalCurrency: string;
  /** 1 is January. */
  readonly fiscalYearStartMonth: number;
  /** Nothing posts on or before this date. */
  readonly lockDate?: Temporal.PlainDate;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AccountingSetupInput {
  /** Default: the `functionalCurrency` option, `EUR` out of the box. */
  readonly functionalCurrency?: string;
  /** Default: the `fiscalYearStartMonth` option, 1 out of the box. */
  readonly fiscalYearStartMonth?: number;
}

/** An account in the chart of accounts. */
export interface AccountingAccount {
  readonly id: string;
  readonly organizationId: string;
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  readonly subtype?: string;
  readonly parentId?: string;
  /** Lines on the account must be in this currency. */
  readonly currency?: string;
  readonly reconcilable: boolean;
  readonly normalSide: AccountNormalSide;
  /** 1 for a top-level account, one more than its parent's otherwise. */
  readonly level: number;
  /** A line on the account takes this tax code when it names none. */
  readonly defaultTaxCodeId?: string;
  /** An inactive account takes no new lines. */
  readonly active: boolean;
  readonly roles: readonly AccountRole[];
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AccountingAccountInput {
  /** Saving a code again updates that account. */
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  /** One of the `subtypes` option. */
  readonly subtype?: string;
  readonly parentId?: string;
  readonly currency?: string;
  readonly reconcilable?: boolean;
  /** Default: debit for assets and expenses, credit for the rest. */
  readonly normalSide?: AccountNormalSide;
  readonly defaultTaxCodeId?: string;
  /** Default: true. */
  readonly active?: boolean;
  /** Changes this account, code included. */
  readonly accountId?: string;
}

export interface AccountingJournal {
  readonly id: string;
  readonly organizationId: string;
  readonly code: string;
  readonly name: string;
  readonly type: JournalType;
  /** The bank or cash account a bank or cash journal posts against. */
  readonly defaultAccountId?: string;
  /** The account a bank or cash journal's lines post against. */
  readonly contraAccountId?: string;
  /** The bank account of the banking block the journal belongs to. */
  readonly bankAccountId?: string;
  readonly currency?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AccountingJournalInput {
  /** Upper-case letters, digits, `_` and `-`; saving a code again updates it. */
  readonly code: string;
  readonly name: string;
  readonly type: JournalType;
  readonly defaultAccountId?: string;
  readonly contraAccountId?: string;
  readonly bankAccountId?: string;
  readonly currency?: string;
  readonly journalId?: string;
}

/** A month of a fiscal year. */
/** What `accounting.closePeriodIfClear` returns. */
export type PeriodCloseResult =
  | { readonly closed: true; readonly period: AccountingPeriod }
  | { readonly closed: false; readonly blockers: readonly string[] };

export interface AccountingPeriod {
  readonly id: string;
  readonly organizationId: string;
  /** The calendar year the fiscal year starts in. */
  readonly fiscalYear: number;
  readonly number: number;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn: Temporal.PlainDate;
  readonly status: AccountingPeriodStatus;
  readonly closedAt?: Temporal.Instant;
  readonly closedBy?: string;
  readonly lockedAt?: Temporal.Instant;
  readonly lockedBy?: string;
}

/** An analysis dimension such as project or department, with its values. */
export interface AccountingDimension {
  readonly id: string;
  readonly organizationId: string;
  /** The key lines use in their `dimensions` object. */
  readonly key: string;
  readonly name: string;
  readonly values: readonly {
    readonly id: string;
    readonly code: string;
    readonly name: string;
    readonly archivedAt?: Temporal.Instant;
  }[];
  readonly createdAt: Temporal.Instant;
}

export interface AccountingDimensionValueInput {
  /** Saving a code again updates that value. */
  readonly code: string;
  readonly name: string;
  readonly archived?: boolean;
}

export type TaxCodeKind = "sales" | "purchase";

export interface AccountingFxRateInput {
  readonly base: string;
  readonly quote: string;
  readonly onDate: Temporal.PlainDate;
  /** One unit of `base` costs `rate` units of `quote`, as a decimal string. */
  readonly rate: string;
}

/**
 * One line of an entry. A `Money` amount must be in the functional currency; a
 * bigint is minor units of it. A line in another currency gives
 * `amountCurrency` and, without `debit` or `credit`, converts at `fxRate` or
 * the rate on the entry date.
 */
export interface AccountingLineInput {
  /** The account's id, or `accountCode` instead. */
  readonly accountId?: string;
  readonly accountCode?: string;
  readonly debit?: bigint | Money;
  readonly credit?: bigint | Money;
  /** The transaction amount, signed: positive is a debit. */
  readonly amountCurrency?: Money;
  /** One unit of the line's currency in the functional currency. */
  readonly fxRate?: string;
  readonly taxCodeId?: string;
  /** The tax in the amount, in minor units; at most the line's amount. */
  readonly taxAmount?: bigint;
  /** The customer, supplier or employee the line concerns. */
  readonly partyId?: string;
  /** Dimension keys to value codes. */
  readonly dimensions?: Readonly<Record<string, string>>;
  readonly description?: string;
}

export interface AccountingLine {
  readonly id: string;
  readonly accountId: string;
  readonly accountCode: string;
  readonly accountName: string;
  /** Minor units of the functional currency. */
  readonly debit: bigint;
  readonly credit: bigint;
  readonly currency: string;
  /** Minor units of `currency`, signed: positive is a debit. */
  readonly amountCurrency: bigint;
  readonly fxRate?: string;
  readonly taxCodeId?: string;
  readonly taxAmount: bigint;
  readonly partyId?: string;
  readonly dimensions: Readonly<Record<string, string>>;
  readonly description?: string;
}

/** A journal entry. `F` types the extra columns the `fields` schema describes. */
export interface AccountingEntry<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly journalId: string;
  /** `<journal>-<fiscal year>-<sequence>`, set when it posts. */
  readonly number?: string;
  readonly fiscalYear?: number;
  readonly entryDate: Temporal.PlainDate;
  readonly periodId?: string;
  readonly status: AccountingEntryStatus;
  readonly reference?: string;
  readonly sourceType?: string;
  readonly sourceId?: string;
  /** The entry this one reverses. */
  readonly reversesId?: string;
  readonly memo?: string;
  /** The memo's translation key when a block wrote it (`invoice.payment`). */
  readonly memoKey?: string;
  /** The raw values the memo names, for the app's own wording of `memoKey`. */
  readonly memoParams?: Readonly<Record<string, unknown>>;
  /** The sum of the debits. */
  readonly total: bigint;
  /** On `getEntry` and writes; `entries` leaves them out. */
  readonly lines?: readonly AccountingLine[];
  readonly postedAt?: Temporal.Instant;
  readonly postedBy?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface AccountingEntryInput<F extends object = Record<never, never>> {
  readonly journalId: string;
  readonly entryDate: Temporal.PlainDate;
  readonly lines: readonly AccountingLineInput[];
  readonly memo?: string;
  readonly reference?: string;
  /** The document the entry books; one entry per document until reversed. */
  readonly sourceType?: string;
  readonly sourceId?: string;
  /** Replaces this draft's header and lines. */
  readonly entryId?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface AccountingEntryListOptions {
  readonly journalId?: string;
  readonly status?: AccountingEntryStatus;
  readonly since?: Temporal.PlainDate;
  readonly until?: Temporal.PlainDate;
  readonly pageSize?: number;
}

export interface AccountingReportOptions {
  readonly since?: Temporal.PlainDate;
  readonly until?: Temporal.PlainDate;
  /** Only lines whose dimensions contain these keys and values. */
  readonly dimensions?: Readonly<Record<string, string>>;
}

export interface TrialBalanceRow {
  readonly accountId: string;
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  /** Before `since`; debit balances are positive. */
  readonly opening: bigint;
  readonly debit: bigint;
  readonly credit: bigint;
  readonly closing: bigint;
}

export interface TrialBalance {
  readonly accounts: readonly TrialBalanceRow[];
  readonly totals: {
    readonly opening: bigint;
    readonly debit: bigint;
    readonly credit: bigint;
    readonly closing: bigint;
  };
}

/** An account's amount on a report, positive on its natural side. */
export interface ReportLine {
  readonly accountId: string;
  readonly code: string;
  readonly name: string;
  readonly type: AccountType;
  readonly subtype?: string;
  readonly amount: bigint;
}

export interface ProfitAndLoss {
  readonly income: readonly ReportLine[];
  readonly expenses: readonly ReportLine[];
  readonly totalIncome: bigint;
  readonly totalExpenses: bigint;
  readonly netIncome: bigint;
}

export interface BalanceSheet {
  readonly asOf: Temporal.PlainDate;
  readonly assets: readonly ReportLine[];
  readonly liabilities: readonly ReportLine[];
  readonly equity: readonly ReportLine[];
  /** Income less expenses not yet closed into retained earnings. */
  readonly currentEarnings: bigint;
  readonly totalAssets: bigint;
  readonly totalLiabilities: bigint;
  /** Equity with the current earnings. */
  readonly totalEquity: bigint;
  readonly balanced: boolean;
}

export interface GeneralLedgerLine {
  readonly entryId: string;
  readonly number: string;
  readonly entryDate: Temporal.PlainDate;
  readonly journalId: string;
  readonly description?: string;
  readonly partyId?: string;
  readonly debit: bigint;
  readonly credit: bigint;
  /** The running balance; debit balances are positive. */
  readonly balance: bigint;
}

export interface GeneralLedger {
  readonly account: {
    readonly id: string;
    readonly code: string;
    readonly name: string;
    readonly type: AccountType;
  };
  readonly opening: bigint;
  readonly lines: readonly GeneralLedgerLine[];
  readonly closing: bigint;
}

export interface FiscalYearClose {
  readonly organizationId: string;
  readonly fiscalYear: number;
  /** Missing when the year had no income or expenses to close. */
  readonly closingEntryId?: string;
}

export interface Accounting<F extends object = Record<never, never>>
  extends AccountingPostings, AccountingLedger {
  /**
   * Sets the functional currency and fiscal year start, and with the `generic`
   * chart adds its accounts, roles and journals. Needs `accounting.manage`.
   */
  setup(input: {
    organizationId: string;
    input?: AccountingSetupInput | undefined;
  }): AsyncResult<AccountingSetup>;
  /**
   * Sets accounting up and opens the periods of `fiscalYear`: `setup` then
   * `openFiscalYear`. Both need `accounting.manage`; when opening fails the
   * settings stay in place and a repeat call continues from there.
   */
  initialize(input: {
    organizationId: string;
    fiscalYear: number;
    input?: AccountingSetupInput | undefined;
  }): AsyncResult<{
    readonly settings: AccountingSetup;
    readonly periods: readonly AccountingPeriod[];
  }>;
  /**
   * The profit and loss from the start of the fiscal year (from the settings'
   * `fiscalYearStartMonth`) to `asOf` (default today). Without settings it
   * fails with `ACCOUNTING_NOT_SET_UP`.
   */
  yearToDate(input: {
    organizationId: string;
    asOf?: Temporal.PlainDate | undefined;
    dimensions?: Readonly<Record<string, string>> | undefined;
  }): AsyncResult<{
    readonly since: Temporal.PlainDate;
    readonly until: Temporal.PlainDate;
    readonly report: ProfitAndLoss;
  }>;
  settings(organizationId: string): AsyncResult<AccountingSetup | undefined>;
  /** Nothing posts on or before `lockDate`. Needs `accounting.close`. */
  setLockDate(input: {
    organizationId: string;
    lockDate: Temporal.PlainDate | null;
  }): AsyncResult<AccountingSetup>;
  /** Needs `accounting.manage`. */
  saveAccount(input: {
    organizationId: string;
    input: AccountingAccountInput;
  }): AsyncResult<AccountingAccount>;
  archiveAccount(input: {
    accountId: string;
    archived?: boolean | undefined;
  }): AsyncResult<AccountingAccount>;
  /** Brings an archived account back so entries post to it again. */
  restoreAccount(accountId: string): AsyncResult<AccountingAccount>;
  /** Maps a role to an account, or clears it with `null`; returns every role. */
  setAccountRole(input: {
    organizationId: string;
    role: AccountRole;
    accountId: string | null;
  }): AsyncResult<Readonly<Partial<Record<AccountRole, string>>>>;
  /**
   * The chart of accounts, by code.
   *
   * @deprecated Use `accountPage`, which pages by keyset and takes `q`, sorts,
   * array filters and a count (ADR 1077).
   */
  accounts(
    input: { organizationId: string } & { readonly includeArchived?: boolean },
  ): AsyncResult<readonly AccountingAccount[]>;
  /**
   * One keyset page of the chart of accounts, by code. `filters` takes `type`
   * and `active` as lists and `archived` as `["true"]` for the archived ones;
   * `q` searches the code and name.
   */
  accountPage(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<AccountingAccount>>;
  /**
   * The values of each facet (`type`, `active`) and how many accounts hold
   * each.
   */
  accountFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many accounts match the page's filters. */
  accountCount(
    options: CountOptions & RequiredTenantOption,
  ): AsyncResult<Count>;
  /** Needs `accounting.manage`. */
  saveJournal(input: {
    organizationId: string;
    input: AccountingJournalInput;
  }): AsyncResult<AccountingJournal>;
  journals(organizationId: string): AsyncResult<readonly AccountingJournal[]>;
  /**
   * Adds the twelve monthly periods of a fiscal year. Needs
   * `accounting.manage`.
   */
  openFiscalYear(input: {
    organizationId: string;
    fiscalYear: number;
  }): AsyncResult<readonly AccountingPeriod[]>;
  periods(input: {
    organizationId: string;
    fiscalYear?: number | undefined;
  }): AsyncResult<readonly AccountingPeriod[]>;
  /** Needs `accounting.manage`. */
  saveDimension(input: {
    organizationId: string;
    key: string;
    name: string;
  }): AsyncResult<AccountingDimension>;
  saveDimensionValue(input: {
    dimensionId: string;
    input: AccountingDimensionValueInput;
  }): AsyncResult<AccountingDimension>;
  dimensions(
    organizationId: string,
  ): AsyncResult<readonly AccountingDimension[]>;
  /** Needs `accounting.manage`. */
  setFxRate(input: {
    organizationId: string;
    input: AccountingFxRateInput;
  }): AsyncResult<AccountingFxRateInput>;
  /** The latest rate on or before `onDate`, direct or inverted, as a decimal. */
  fxRate(input: {
    organizationId: string;
    base: string;
    quote: string;
    onDate: Temporal.PlainDate;
  }): AsyncResult<string>;
  /** Creates a draft, or replaces one. Needs `accounting.write`. */
  saveEntry(input: AccountingEntryInput<F>): AsyncResult<AccountingEntry<F>>;
  /**
   * Checks the entry balances, falls in an open period after the lock date and
   * names known dimension values, then numbers it. Needs `accounting.post`.
   */
  postEntry(entryId: string): AsyncResult<AccountingEntry<F>>;
  /**
   * Posts an entry of opposite lines dated `entryDate` (default the original's)
   * and marks the original reversed; returns the reversal. Needs
   * `accounting.post`.
   */
  reverseEntry(input: {
    entryId: string;
    entryDate?: Temporal.PlainDate | undefined;
  }): AsyncResult<AccountingEntry<F>>;
  /** Drafts only. Needs `accounting.write`. */
  deleteEntry(entryId: string): AsyncResult<AccountingEntry<F>>;
  getEntry(entryId: string): AsyncResult<AccountingEntry<F> | undefined>;
  /**
   * The newest first, without lines.
   *
   * @deprecated Use `entryPage`, which pages by keyset and takes `q`, sorts,
   * array filters and a count (ADR 1077).
   */
  entries(
    input: { organizationId: string } & AccountingEntryListOptions,
  ): AsyncResult<readonly AccountingEntry<F>[]>;
  /**
   * One keyset page of entries without lines, newest entry date first.
   * `filters` takes `status` and `journalId` as lists and `since` and `until`
   * as dates; `q` searches the number, reference and memo.
   */
  entryPage(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<AccountingEntry<F>>>;
  /** The values of the `status` facet and how many entries hold each. */
  entryFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many entries match the page's filters. */
  entryCount(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** What keeps a period from closing, such as `draft_entries`. */
  closeBlockers(periodId: string): AsyncResult<readonly string[]>;
  /** Needs `accounting.close`. */
  closePeriod(periodId: string): AsyncResult<AccountingPeriod>;
  /**
   * Closes the period when nothing blocks it, in one call
   * (`close_accounting_period_if_clear`, ADR 1235). A blocked period is not an
   * error: the result lists the blockers and changes nothing. Needs
   * `accounting.close`.
   */
  closePeriodIfClear(periodId: string): AsyncResult<PeriodCloseResult>;
  /** Needs `accounting.close` and a reason. */
  reopenPeriod(input: {
    periodId: string;
    reason: string;
  }): AsyncResult<AccountingPeriod>;
  /**
   * Moves the year's income and expenses to retained earnings in one closing
   * entry, then closes its periods. Needs `accounting.close`.
   */
  closeFiscalYear(input: {
    organizationId: string;
    fiscalYear: number;
  }): AsyncResult<FiscalYearClose>;
  trialBalance(
    input: { organizationId: string } & AccountingReportOptions,
  ): AsyncResult<TrialBalance>;
  /** Without year-end closing entries. */
  profitAndLoss(
    input: { organizationId: string } & AccountingReportOptions,
  ): AsyncResult<ProfitAndLoss>;
  balanceSheet(
    input: { organizationId: string } & {
      readonly asOf?: Temporal.PlainDate;
      readonly dimensions?: Readonly<Record<string, string>>;
    },
  ): AsyncResult<BalanceSheet>;
  generalLedger(
    input: { accountId: string } & {
      readonly since?: Temporal.PlainDate;
      readonly until?: Temporal.PlainDate;
    },
  ): AsyncResult<GeneralLedger>;
}

/** The `accounting` SQL module as typed calls. */
export function createAccounting<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AccountingOptions<S>): Accounting<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(options.fields, "entry fields");

  const entry = (fn: string) => (value: unknown) => entryOf(value, fn);
  const period = (fn: string) => (value: unknown) => periodOf(value, fn);

  const accountList = entityList<AccountingAccount, RequiredTenantOption>({
    entity: "accounting account",
    surface: accountingAccountListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_accounting_accounts",
    rowOf: (row, fn) => accountOf(row, fn),
  });

  const entryList = entityList<AccountingEntry, RequiredTenantOption>({
    entity: "accounting entry",
    surface: accountingEntryListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_accounting_entries",
    rowOf: (row, fn) => entryOf(row, fn),
  });

  const client: Accounting<F> = {
    initialize: ({ organizationId, fiscalYear, input }) =>
      hooked
        .setup({ organizationId, input })
        .andThen((settings) =>
          hooked
            .openFiscalYear({ organizationId, fiscalYear })
            .map((periods) => ({ settings, periods })),
        ),
    yearToDate: ({ organizationId, asOf, dimensions }) =>
      hooked.settings(organizationId).andThen((settings) => {
        if (settings === undefined) {
          return AsyncResult.err(
            dbError("not_found", "accounting isn't set up", {
              hint: "ACCOUNTING_NOT_SET_UP",
            }),
          );
        }

        return AsyncResult.from(async () => {
          const until = asOf ?? temporal().Now.plainDateISO();
          const start = settings.fiscalYearStartMonth;

          const since = temporal().PlainDate.from({
            year: until.month >= start ? until.year : until.year - 1,
            month: start,
            day: 1,
          });

          const report = await hooked.profitAndLoss({
            organizationId,
            since,
            until,
            ...(dimensions === undefined ? {} : { dimensions }),
          });

          return report.ok ? ok({ since, until, report: report.data }) : report;
        });
      }),
    ...accountingPostings(call),
    ...accountingLedger(call),
    setup: ({ organizationId, input = {} }) =>
      call(
        "setup_accounting",
        {
          tenant: organizationId,
          functional_currency: input.functionalCurrency ?? null,
          fiscal_year_start_month: input.fiscalYearStartMonth ?? null,
        },
        (value) => settingsOf(value, "setup_accounting"),
      ),
    settings: (organizationId) =>
      call(
        "get_accounting_settings",
        { tenant: organizationId },
        maybe("get_accounting_settings", settingsOf),
      ),
    setLockDate: ({ organizationId, lockDate }) =>
      call(
        "set_accounting_lock_date",
        { tenant: organizationId, lock_date: lockDate?.toString() ?? null },
        (value) => settingsOf(value, "set_accounting_lock_date"),
      ),
    saveAccount: ({ organizationId, input }) =>
      call(
        "upsert_accounting_account",
        {
          tenant: organizationId,
          code: input.code,
          name: input.name,
          type: input.type,
          subtype: input.subtype ?? null,
          parent_id: input.parentId ?? null,
          currency: input.currency ?? null,
          reconcilable: input.reconcilable ?? null,
          account_id: input.accountId ?? null,
          normal_side: input.normalSide ?? null,
          default_tax_code_id: input.defaultTaxCodeId ?? null,
          active: input.active ?? null,
        },
        (value) => accountOf(value, "upsert_accounting_account"),
      ),
    archiveAccount: ({ accountId, archived = true }) =>
      call(
        "archive_accounting_account",
        { account_id: accountId, archived },
        (value) => accountOf(value, "archive_accounting_account"),
      ),
    restoreAccount: (accountId) =>
      call(
        "archive_accounting_account",
        { account_id: accountId, archived: false },
        (value) => accountOf(value, "archive_accounting_account"),
      ),
    setAccountRole: ({ organizationId, role, accountId }) =>
      call(
        "set_accounting_account_role",
        { tenant: organizationId, role, account_id: accountId },
        (value) => rolesOf(value, "set_accounting_account_role"),
      ),
    accountPage: (page) => accountList.page(page),
    accountFacets: (facets) => accountList.facets(facets),
    accountCount: (count) => accountList.count(count),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    accounts: ({ organizationId, ...list }) =>
      call(
        "list_accounting_accounts",
        {
          tenant: organizationId,
          include_archived: list.includeArchived ?? false,
        },
        many("list_accounting_accounts", accountOf),
      ),
    saveJournal: ({ organizationId, input }) =>
      call(
        "upsert_accounting_journal",
        {
          tenant: organizationId,
          code: input.code,
          name: input.name,
          type: input.type,
          default_account_id: input.defaultAccountId ?? null,
          currency: input.currency ?? null,
          journal_id: input.journalId ?? null,
          contra_account_id: input.contraAccountId ?? null,
          bank_account_id: input.bankAccountId ?? null,
        },
        (value) => journalOf(value, "upsert_accounting_journal"),
      ),
    journals: (organizationId) =>
      call(
        "list_accounting_journals",
        { tenant: organizationId },
        many("list_accounting_journals", journalOf),
      ),
    openFiscalYear: ({ organizationId, fiscalYear }) =>
      call(
        "open_fiscal_year",
        { tenant: organizationId, fiscal_year: fiscalYear },
        many("open_fiscal_year", periodOf),
      ),
    periods: ({ organizationId, fiscalYear }) =>
      call(
        "list_accounting_periods",
        { tenant: organizationId, fiscal_year: fiscalYear ?? null },
        many("list_accounting_periods", periodOf),
      ),
    saveDimension: ({ organizationId, key, name }) =>
      call(
        "upsert_accounting_dimension",
        { tenant: organizationId, key, name },
        (value) => dimensionOf(value, "upsert_accounting_dimension"),
      ),
    saveDimensionValue: ({ dimensionId, input }) =>
      call(
        "upsert_accounting_dimension_value",
        {
          dimension_id: dimensionId,
          code: input.code,
          name: input.name,
          archived: input.archived ?? false,
        },
        (value) => dimensionOf(value, "upsert_accounting_dimension_value"),
      ),
    dimensions: (organizationId) =>
      call(
        "list_accounting_dimensions",
        { tenant: organizationId },
        many("list_accounting_dimensions", dimensionOf),
      ),
    setFxRate: ({ organizationId, input }) =>
      call(
        "set_accounting_fx_rate",
        {
          tenant: organizationId,
          base: input.base,
          quote: input.quote,
          on_date: input.onDate.toString(),
          rate: input.rate,
        },
        (value) => fxRateOf(value, "set_accounting_fx_rate"),
      ),
    fxRate: ({ organizationId, base, quote, onDate }) =>
      call(
        "accounting_fx_rate",
        { tenant: organizationId, base, quote, on_date: onDate.toString() },
        decimalOf,
      ),
    saveEntry: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "upsert_accounting_entry",
            {
              journal_id: input.journalId,
              entry_date: input.entryDate.toString(),
              lines: input.lines.map(lineArg),
              memo: input.memo ?? null,
              reference: input.reference ?? null,
              source_type: input.sourceType ?? null,
              source_id: input.sourceId ?? null,
              entry_id: input.entryId ?? null,
              ...(checked === undefined ? {} : { fields: checked }),
            },
            entry("upsert_accounting_entry"),
          ).andThen(fields.row),
        ),
    postEntry: (entryId) =>
      call(
        "post_accounting_entry",
        { entry_id: entryId },
        entry("post_accounting_entry"),
      ).andThen(fields.row),
    reverseEntry: ({ entryId, entryDate }) =>
      call(
        "reverse_accounting_entry",
        { entry_id: entryId, entry_date: entryDate?.toString() ?? null },
        entry("reverse_accounting_entry"),
      ).andThen(fields.row),
    deleteEntry: (entryId) =>
      call(
        "delete_accounting_entry",
        { entry_id: entryId },
        entry("delete_accounting_entry"),
      ).andThen(fields.row),
    getEntry: (entryId) =>
      call(
        "get_accounting_entry",
        { entry_id: entryId },
        maybe("get_accounting_entry", entryOf),
      ).andThen((found) =>
        found === undefined ? AsyncResult.ok(undefined) : fields.row(found),
      ),
    entryPage: (page) =>
      entryList
        .page(page)
        .andThen((read) =>
          fields.rows(read.items).map((items) => ({ ...read, items })),
        ),
    entryFacets: (facets) => entryList.facets(facets),
    entryCount: (count) => entryList.count(count),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    entries: ({ organizationId, ...list }) =>
      call(
        "list_accounting_entries",
        {
          tenant: organizationId,
          journal_id: list.journalId ?? null,
          status: list.status ?? null,
          since: list.since?.toString() ?? null,
          until: list.until?.toString() ?? null,
          page_size: list.pageSize ?? null,
        },
        many("list_accounting_entries", entryOf),
      ).andThen(fields.rows),
    closeBlockers: (periodId) =>
      call(
        "accounting_period_close_blockers",
        { period_id: periodId },
        (value) => (Array.isArray(value) ? value.map(textOf) : []),
      ),
    closePeriod: (periodId) =>
      call(
        "close_accounting_period",
        { period_id: periodId },
        period("close_accounting_period"),
      ),
    closePeriodIfClear: (periodId) =>
      call(
        "close_accounting_period_if_clear",
        { period_id: periodId },
        (value) => {
          const row = recordOf(value, "close_accounting_period_if_clear");

          return row["closed"] === true
            ? {
                closed: true as const,
                period: period("close_accounting_period_if_clear")(
                  row["period"],
                ),
              }
            : {
                closed: false as const,
                blockers: Array.isArray(row["blockers"])
                  ? row["blockers"].map(textOf)
                  : [],
              };
        },
      ),
    reopenPeriod: ({ periodId, reason }) =>
      call(
        "reopen_accounting_period",
        { period_id: periodId, reason },
        period("reopen_accounting_period"),
      ),
    closeFiscalYear: ({ organizationId, fiscalYear }) =>
      call(
        "close_fiscal_year",
        { tenant: organizationId, fiscal_year: fiscalYear },
        (value) => fiscalYearCloseOf(value, "close_fiscal_year"),
      ),
    trialBalance: ({ organizationId, ...report }) =>
      call(
        "accounting_trial_balance",
        {
          tenant: organizationId,
          since: report.since?.toString() ?? null,
          until: report.until?.toString() ?? null,
          dimensions: report.dimensions ?? {},
        },
        (value) => trialBalanceOf(value, "accounting_trial_balance"),
      ),
    profitAndLoss: ({ organizationId, ...report }) =>
      call(
        "accounting_profit_and_loss",
        {
          tenant: organizationId,
          since: report.since?.toString() ?? null,
          until: report.until?.toString() ?? null,
          dimensions: report.dimensions ?? {},
        },
        (value) => profitAndLossOf(value, "accounting_profit_and_loss"),
      ),
    balanceSheet: ({ organizationId, ...report }) =>
      call(
        "accounting_balance_sheet",
        {
          tenant: organizationId,
          as_of: report.asOf?.toString() ?? null,
          dimensions: report.dimensions ?? {},
        },
        (value) => balanceSheetOf(value, "accounting_balance_sheet"),
      ),
    generalLedger: ({ accountId, ...report }) =>
      call(
        "accounting_general_ledger",
        {
          account_id: accountId,
          since: report.since?.toString() ?? null,
          until: report.until?.toString() ?? null,
        },
        (value) => generalLedgerOf(value, "accounting_general_ledger"),
      ),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Accounting<F> = withBlockHooks(client, options.hooks, {
    block: "accounting",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
