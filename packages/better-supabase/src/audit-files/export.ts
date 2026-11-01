import type {
  AuditAccount,
  AuditAccountType,
  AuditBooks,
  AuditEntry,
  AuditFileAdapter,
  AuditHeader,
  AuditJournal,
  AuditJournalType,
  AuditOpeningBalance,
  AuditParty,
  AuditTaxCode,
  AuditWarning,
} from "./model.ts";

import { temporal } from "../core/temporal-required.ts";
import { AuditFileError } from "./model.ts";

type Outcome<T> = PromiseLike<
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { readonly message: string } }
>;

/**
 * The ledger reads an export needs. The `accounting` client fits as is:
 * `accounts`, `journalListing` and `openingBalances`.
 */
export interface AuditLedgerSource {
  accounts(input: {
    organizationId: string;
  }): Outcome<
    readonly {
      readonly id: string;
      readonly code: string;
      readonly name: string;
      readonly type: AuditAccountType;
      readonly active: boolean;
    }[]
  >;
  journalListing(input: {
    readonly organizationId: string;
    readonly since: Temporal.PlainDate;
    readonly until: Temporal.PlainDate;
  }): Outcome<{
    readonly journals: readonly {
      readonly code: string;
      readonly name: string;
      readonly type: string;
      readonly entries: readonly {
        readonly id: string;
        readonly number?: string | undefined;
        readonly entryDate: Temporal.PlainDate;
        readonly reference?: string | undefined;
        readonly memo?: string | undefined;
        readonly lines: readonly {
          readonly accountCode: string;
          readonly debit: bigint;
          readonly credit: bigint;
          readonly taxAmount: bigint;
          readonly partyId?: string | undefined;
          readonly description?: string | undefined;
        }[];
      }[];
    }[];
  }>;
  openingBalances(input: {
    organizationId: string;
    fiscalYear: number;
  }): Outcome<{
    readonly posted: boolean;
    readonly balances: readonly {
      readonly accountId: string;
      readonly partyId?: string | undefined;
      readonly amount: bigint;
    }[];
  }>;
}

/**
 * The period to export: the fiscal `year`, which is the calendar year unless
 * `from` and `to` say otherwise.
 */
export interface AuditSelection {
  readonly year: number;
  readonly from?: Temporal.PlainDate;
  readonly to?: Temporal.PlainDate;
}

export interface ExportAuditFileOptions {
  readonly organizationId: string;
  /** The company the ledger belongs to; the ledger does not hold it. */
  readonly company: AuditHeader["company"];
  /** ISO 4217 code of the functional currency. */
  readonly currency: string;
  /**
   * The fiscal year, as `{ year }` for the calendar year or with `from` and
   * `to` for another year or a part of one.
   */
  readonly selection: AuditSelection;
  /** Customers and suppliers to write; the ledger keeps none itself. */
  readonly parties?: readonly AuditParty[];
  readonly taxCodes?: readonly AuditTaxCode[];
  readonly software?: AuditHeader["software"];
}

export interface ExportAuditFileResult {
  readonly xml: string;
  readonly books: AuditBooks;
  /** What the file could not carry; never empty by accident. */
  readonly warnings: readonly AuditWarning[];
}

const JOURNAL_TYPES: readonly AuditJournalType[] = [
  "sales",
  "purchase",
  "bank",
  "cash",
  "general",
];

const journalType = (value: string): AuditJournalType =>
  JOURNAL_TYPES.find((type) => type === value) ?? "general";

async function read<T>(outcome: Outcome<T>, what: string): Promise<T> {
  const result = await outcome;

  if (!result.ok) {
    throw new AuditFileError(
      "AUDIT_FILE_INVALID",
      `reading ${what} failed: ${result.error.message}`,
    );
  }

  return result.data;
}

/** Reads a fiscal year of the ledger as the books an adapter writes. */
export async function booksFromLedger(
  source: AuditLedgerSource,
  options: ExportAuditFileOptions,
): Promise<{
  readonly books: AuditBooks;
  readonly warnings: readonly AuditWarning[];
}> {
  const { PlainDate } = temporal();
  const { selection } = options;
  const warnings: AuditWarning[] = [];

  const from =
    selection.from ??
    PlainDate.from({ year: selection.year, month: 1, day: 1 });

  const to =
    selection.to ??
    PlainDate.from({ year: selection.year, month: 12, day: 31 });

  const [accounts, listing, opening] = await Promise.all([
    read(
      source.accounts({ organizationId: options.organizationId }),
      "the accounts",
    ),
    read(
      source.journalListing({
        organizationId: options.organizationId,
        since: from,
        until: to,
      }),
      "the journal listing",
    ),
    read(
      source.openingBalances({
        organizationId: options.organizationId,
        fiscalYear: selection.year,
      }),
      "the opening balances",
    ),
  ]);

  const codeOf = new Map(accounts.map((account) => [account.id, account.code]));

  const openingBalances: AuditOpeningBalance[] = [];

  if (opening.posted && opening.balances.length > 0) {
    warnings.push({
      code: "AUDIT_EXPORT_OMITTED",
      message:
        "the opening balances of the year are posted as an entry, so they are in the journals and not repeated as opening balances",
      count: opening.balances.length,
    });
  } else {
    for (const balance of opening.balances) {
      const accountCode = codeOf.get(balance.accountId);

      if (accountCode === undefined) {
        throw new AuditFileError(
          "AUDIT_FILE_INVALID",
          `an opening balance names account ${balance.accountId}, which is not an account of the organization`,
        );
      }

      openingBalances.push({
        fiscalYear: selection.year,
        accountCode,
        ...(balance.partyId === undefined
          ? {}
          : { partyCode: balance.partyId }),
        amount: balance.amount,
      });
    }
  }

  const journals: AuditJournal[] = [];
  const entries: AuditEntry[] = [];

  for (const journal of listing.journals) {
    journals.push({
      code: journal.code,
      name: journal.name,
      type: journalType(journal.type),
    });

    for (const entry of journal.entries) {
      entries.push({
        journalCode: journal.code,
        id: entry.number ?? entry.id,
        date: entry.entryDate.toString(),
        ...(entry.memo === undefined ? {} : { description: entry.memo }),
        ...(entry.reference === undefined
          ? {}
          : { reference: entry.reference }),
        lines: entry.lines.map((line) => ({
          accountCode: line.accountCode,
          debit: line.debit,
          credit: line.credit,
          ...(line.description === undefined
            ? {}
            : { description: line.description }),
          ...(line.partyId === undefined ? {} : { partyCode: line.partyId }),
          ...(line.taxAmount === 0n ? {} : { taxAmount: line.taxAmount }),
        })),
      });
    }
  }

  const books: AuditBooks = {
    header: {
      fiscalYear: selection.year,
      startDate: from.toString(),
      endDate: to.toString(),
      currency: options.currency,
      company: options.company,
      ...(options.software === undefined ? {} : { software: options.software }),
    },
    accounts: accounts
      .filter((account) => account.active)
      .map((account): AuditAccount => ({
        code: account.code,
        name: account.name,
        type: account.type,
      })),
    parties: options.parties ?? [],
    taxCodes: options.taxCodes ?? [],
    journals,
    openingBalances,
    entries,
  };

  return { books, warnings };
}

/**
 * Writes a fiscal year of the ledger as an audit file. The opening balances
 * that are not yet posted travel as opening balances; posted entries travel in
 * their journals.
 */
export async function exportAuditFile(
  adapter: AuditFileAdapter,
  source: AuditLedgerSource,
  options: ExportAuditFileOptions,
): Promise<ExportAuditFileResult> {
  const { books, warnings } = await booksFromLedger(source, options);

  const merged = new Set(
    books.openingBalances
      .filter((balance) => balance.partyCode !== undefined)
      .map((balance) => balance.accountCode),
  );

  const all = [...warnings];

  if (merged.size > 0 && adapter.format === "SAF-T") {
    all.push({
      code: "AUDIT_OPENING_PARTY_MERGED",
      message: `opening balances of ${merged.size} accounts per customer or supplier were written per account`,
      count: merged.size,
    });
  }

  return { xml: [...adapter.export(books)].join(""), books, warnings: all };
}
