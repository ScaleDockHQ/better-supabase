/** The five account types of the accounting block. */
export type AuditAccountType =
  | "asset"
  | "liability"
  | "equity"
  | "income"
  | "expense";

export type AuditJournalType =
  | "sales"
  | "purchase"
  | "bank"
  | "cash"
  | "general";

/** What the header of a file says about the books it holds. */
export interface AuditHeader {
  readonly fiscalYear: number;
  /** `YYYY-MM-DD`. */
  readonly startDate: string;
  readonly endDate: string;
  /** ISO 4217 code of the functional currency. */
  readonly currency: string;
  readonly company: {
    readonly name: string;
    /** The company's registration number (chamber of commerce, for one). */
    readonly registrationNumber?: string;
    readonly taxId?: string;
    /** ISO 3166-1 alpha-2 country. */
    readonly country?: string;
  };
  readonly software?: { readonly name?: string; readonly version?: string };
}

export interface AuditAccount {
  readonly code: string;
  readonly name: string;
  readonly type: AuditAccountType;
  /** Set when the file does not say and the adapter assumed `type`. */
  readonly typeAssumed?: boolean;
}

/** A customer or a supplier. */
export interface AuditParty {
  readonly kind: "customer" | "supplier";
  readonly code: string;
  readonly name: string;
  readonly taxId?: string;
  readonly country?: string;
  /** The control account of the party, such as the receivables account. */
  readonly accountCode?: string;
}

export interface AuditTaxCode {
  readonly code: string;
  readonly description: string;
  /** The rate in basis points, when the file gives one. */
  readonly rateBps?: number;
  readonly type: "sales" | "purchase";
}

export interface AuditJournal {
  readonly code: string;
  readonly name: string;
  readonly type: AuditJournalType;
}

/** A signed amount per account, a debit balance positive. */
export interface AuditOpeningBalance {
  readonly fiscalYear: number;
  readonly accountCode: string;
  readonly partyCode?: string;
  /** Minor units of the functional currency. */
  readonly amount: bigint;
}

export interface AuditLine {
  readonly accountCode: string;
  /** Minor units; a line has a debit or a credit, never both. */
  readonly debit: bigint;
  readonly credit: bigint;
  readonly description?: string;
  readonly partyCode?: string;
  readonly taxCode?: string;
  readonly taxAmount?: bigint;
}

export interface AuditEntry {
  readonly journalCode: string;
  /** The entry's number in the file; the key of the entry when imported. */
  readonly id: string;
  /** `YYYY-MM-DD`. */
  readonly date: string;
  readonly description?: string;
  readonly reference?: string;
  readonly lines: readonly AuditLine[];
}

/** A finding that did not stop the file; the caller decides what to do. */
export interface AuditWarning {
  readonly code:
    | "AUDIT_CONTROL_TOTAL_MISMATCH"
    | "AUDIT_ELEMENT_UNMAPPED"
    | "AUDIT_ACCOUNT_TYPE_ASSUMED"
    | "AUDIT_PARTY_NOT_IMPORTED"
    | "AUDIT_PARTY_LINK_DROPPED"
    | "AUDIT_TAX_CODE_NOT_IMPORTED"
    | "AUDIT_OPENING_PARTY_MERGED"
    | "AUDIT_EXPORT_OMITTED"
    | "AUDIT_DATABASE_WARNING";
  readonly message: string;
  /** The element path for an unmapped element. */
  readonly path?: string;
  /** How many times it happened. */
  readonly count: number;
}

/** What `parse` yields, in the order of the file. */
export type AuditRecord =
  | { readonly kind: "header"; readonly header: AuditHeader }
  | { readonly kind: "account"; readonly account: AuditAccount }
  | { readonly kind: "party"; readonly party: AuditParty }
  | { readonly kind: "taxCode"; readonly taxCode: AuditTaxCode }
  | { readonly kind: "journal"; readonly journal: AuditJournal }
  | { readonly kind: "openingBalance"; readonly balance: AuditOpeningBalance }
  | { readonly kind: "entry"; readonly entry: AuditEntry }
  | { readonly kind: "warning"; readonly warning: AuditWarning };

/** The books an adapter writes. */
export interface AuditBooks {
  readonly header: AuditHeader;
  readonly accounts: readonly AuditAccount[];
  readonly parties: readonly AuditParty[];
  readonly taxCodes: readonly AuditTaxCode[];
  readonly journals: readonly AuditJournal[];
  readonly openingBalances: readonly AuditOpeningBalance[];
  readonly entries: readonly AuditEntry[];
}

/** A file as a string, bytes or chunks; chunks are read one at a time. */
export type AuditFileSource =
  | string
  | Uint8Array
  | AsyncIterable<string | Uint8Array>
  | Iterable<string | Uint8Array>;

export interface AuditParseLimits {
  /** Deepest element nesting; default 32. */
  readonly maxDepth?: number;
  /** Longest text of one element in characters; default 1,048,576. */
  readonly maxTextLength?: number;
  /** Most elements in one record such as a transaction; default 100,000. */
  readonly maxRecordElements?: number;
}

export interface AuditParseOptions extends AuditParseLimits {
  /** Decimals of the file's amounts; default 2. */
  readonly decimals?: number;
}

/**
 * A reader and writer of one audit file format (ADR 0144). The interface is
 * versioned: a breaking change needs `apiVersion: 2`.
 */
export interface AuditFileAdapter {
  readonly apiVersion: 1;
  /** A stable name such as `saft-oecd-2.00`. */
  readonly key: string;
  /** The format, such as `SAF-T`. */
  readonly format: string;
  /** The version of the format the adapter follows, as in `SPEC_PINS`. */
  readonly version: string;
  /**
   * Reads a file one record at a time, so memory stays flat for a large file.
   * Elements the adapter does not map come as `warning` records at the end.
   */
  parse(
    source: AuditFileSource,
    options?: AuditParseOptions,
  ): AsyncIterable<AuditRecord>;
  /** Writes the books as chunks of XML. */
  export(books: AuditBooks): Iterable<string>;
}

/** Marks `adapter` as an audit file adapter and checks its version. */
export function defineAuditFileAdapter(
  adapter: AuditFileAdapter,
): AuditFileAdapter {
  // A JavaScript caller can pass any version, though the type says 1.
  const version: unknown = adapter.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `audit file adapter "${adapter.key}" has apiVersion ${String(version)}; this release reads apiVersion 1`,
    );
  }

  return adapter;
}

export type AuditFileErrorCode =
  | "AUDIT_XML_INVALID"
  | "AUDIT_XML_LIMIT"
  | "AUDIT_XML_UNSUPPORTED"
  | "AUDIT_FILE_INVALID"
  | "AUDIT_AMOUNT_INVALID";

/** A file that cannot be read; the message names where. */
export class AuditFileError extends Error {
  readonly code: AuditFileErrorCode;

  constructor(code: AuditFileErrorCode, message: string) {
    super(message);
    this.name = "AuditFileError";
    this.code = code;
  }
}
