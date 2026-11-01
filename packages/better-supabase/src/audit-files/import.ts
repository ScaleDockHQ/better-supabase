import type {
  AuditEntry,
  AuditFileAdapter,
  AuditFileSource,
  AuditHeader,
  AuditParseOptions,
  AuditRecord,
  AuditWarning,
} from "./model.ts";

/** One item of an `import_upsert_batch` call (ADR 0141). */
export interface AuditImportItem {
  readonly key: string;
  readonly scope?: string;
  readonly data: Readonly<Record<string, unknown>>;
}

/** What the database answers for one batch. */
export interface AuditUpsertReply {
  readonly inserted: number;
  readonly updated: number;
  readonly unchanged: number;
  readonly conflicted: number;
  readonly errors: readonly {
    readonly key: string | null;
    readonly code: string;
    readonly message: string;
  }[];
  readonly warnings?: readonly {
    readonly key: string | null;
    readonly code: string;
    readonly message: string;
  }[];
}

/**
 * The `imports` client of the imports block, or anything shaped like it.
 * `imports.upsertBatch` fits as is.
 */
export interface AuditImportPort {
  upsertBatch(input: {
    runId: string;
    entity: string;
    items: readonly AuditImportItem[];
  }): PromiseLike<
    | { readonly ok: true; readonly data: AuditUpsertReply }
    | { readonly ok: false; readonly error: { readonly message: string } }
  >;
}

/** The import entities the ledger writes through. */
export interface AuditImportEntities {
  readonly account: string;
  readonly journal: string;
  readonly entry: string;
  readonly openingBalance: string;
  readonly taxCode: string;
  /**
   * The entity customers and suppliers go to. The accounting block has none, so
   * parties are only imported when the app registers a target for them.
   */
  readonly party?: string;
}

export const DEFAULT_AUDIT_ENTITIES: AuditImportEntities = {
  account: "accounting_account",
  journal: "accounting_journal",
  entry: "accounting_entry",
  openingBalance: "accounting_opening_balance",
  taxCode: "tax_code",
};

export interface ImportAuditFileOptions {
  /** The id of the import run (`imports.runs.start`). */
  readonly run: string;
  readonly imports: AuditImportPort;
  /** Entity names that differ from `DEFAULT_AUDIT_ENTITIES`. */
  readonly entities?: Partial<AuditImportEntities>;
  /** Items per `import_upsert_batch` call; default 200. */
  readonly batchSize?: number;
  /** The first day a tax code's rate applies; default `1970-01-01`. */
  readonly taxRateValidFrom?: string;
  /** Limits and decimals for the adapter. */
  readonly parse?: AuditParseOptions;
  /** Called after each batch, for a progress display. */
  readonly onBatch?: (progress: AuditImportProgress) => void;
}

export interface AuditImportProgress {
  readonly entity: string;
  readonly items: number;
}

export interface AuditEntityCounts {
  readonly inserted: number;
  readonly updated: number;
  readonly unchanged: number;
  readonly conflicted: number;
}

export interface AuditImportError {
  readonly entity: string;
  readonly key: string | null;
  readonly code: string;
  readonly message: string;
}

export interface AuditImportResult {
  readonly header: AuditHeader | undefined;
  /** Per entity, what the database did. A repeat shows only `unchanged`. */
  readonly counts: Readonly<Record<string, AuditEntityCounts>>;
  /** Items the database refused, with its reason. */
  readonly errors: readonly AuditImportError[];
  /** What the file or the import left out or changed; never empty by accident. */
  readonly warnings: readonly AuditWarning[];
  /** Whether the whole file was read and no item failed. */
  readonly ok: boolean;
}

class PortFailure extends Error {
  readonly entity: string;

  constructor(entity: string, reason: string) {
    super(`import_upsert_batch failed for ${entity}: ${reason}`);
    this.entity = entity;
  }
}

const DEFAULT_BATCH = 200;
const DEFAULT_RATE_FROM = "1970-01-01";

/** Entities in the order the database needs them. */
const PHASES = [
  "account",
  "taxCode",
  "party",
  "journal",
  "openingBalance",
  "entry",
] as const;

type Phase = (typeof PHASES)[number];

const emptyCounts = (): {
  inserted: number;
  updated: number;
  unchanged: number;
  conflicted: number;
} => ({ inserted: 0, updated: 0, unchanged: 0, conflicted: 0 });

const entryItem = (entry: AuditEntry): AuditImportItem => ({
  key: `${entry.journalCode}/${entry.id}`,
  data: {
    journalCode: entry.journalCode,
    entryDate: entry.date,
    ...(entry.description === undefined ? {} : { memo: entry.description }),
    ...(entry.reference === undefined ? {} : { reference: entry.reference }),
    post: true,
    lines: entry.lines.map((line) => ({
      accountCode: line.accountCode,
      debit: line.debit.toString(),
      credit: line.credit.toString(),
      ...(line.description === undefined
        ? {}
        : { description: line.description }),
      ...(line.taxAmount === undefined
        ? {}
        : { taxAmount: line.taxAmount.toString() }),
    })),
  },
});

/**
 * Reads an audit file and writes it through `import_upsert_batch`, in the order
 * the ledger needs: accounts, tax codes, customers and suppliers, journals,
 * opening balances, then entries. Each record has a key from the file, so a
 * repeat of the same file is all `unchanged` and writes nothing.
 *
 * The file is read as a stream and written in batches, so memory stays flat.
 * Nothing in the file is dropped without a warning: elements the adapter does
 * not map, party links and tax code links the accounting entities cannot hold,
 * and control totals that do not match all come back in `warnings`.
 */
export async function importAuditFile(
  adapter: AuditFileAdapter,
  file: AuditFileSource,
  options: ImportAuditFileOptions,
): Promise<AuditImportResult> {
  const entities: AuditImportEntities = {
    ...DEFAULT_AUDIT_ENTITIES,
    ...options.entities,
  };

  const size = options.batchSize ?? DEFAULT_BATCH;
  const from = options.taxRateValidFrom ?? DEFAULT_RATE_FROM;
  const counts = new Map<string, ReturnType<typeof emptyCounts>>();
  const errors: AuditImportError[] = [];
  const warnings: AuditWarning[] = [];
  const buffers = new Map<Phase, AuditImportItem[]>();

  const openings = new Map<
    string,
    { fiscalYear: number; accountCode: string; amount: bigint }
  >();

  const merged = new Set<string>();
  let header: AuditHeader | undefined;
  let partiesSkipped = 0;
  let partyLinks = 0;
  let taxLinks = 0;

  const entityOf = (phase: Phase): string | undefined =>
    phase === "party" ? entities.party : entities[phase];

  const write = async (
    phase: Phase,
    items: readonly AuditImportItem[],
  ): Promise<void> => {
    const entity = entityOf(phase);

    if (entity === undefined || items.length === 0) {
      return;
    }

    const outcome = await options.imports.upsertBatch({
      runId: options.run,
      entity,
      items,
    });

    if (!outcome.ok) {
      throw new PortFailure(entity, outcome.error.message);
    }

    const total = counts.get(entity) ?? emptyCounts();

    total.inserted += outcome.data.inserted;
    total.updated += outcome.data.updated;
    total.unchanged += outcome.data.unchanged;
    total.conflicted += outcome.data.conflicted;
    counts.set(entity, total);

    for (const error of outcome.data.errors) {
      errors.push({ entity, ...error });
    }

    for (const warning of outcome.data.warnings ?? []) {
      warnings.push({
        code: "AUDIT_DATABASE_WARNING",
        message: `${entity} ${warning.key ?? ""}: ${warning.code}: ${warning.message}`,
        count: 1,
      });
    }

    options.onBatch?.({ entity, items: items.length });
  };

  const flushBefore = async (phase: Phase): Promise<void> => {
    for (const earlier of PHASES.slice(0, PHASES.indexOf(phase))) {
      if (earlier === "openingBalance" && openings.size > 0) {
        buffers.set(
          earlier,
          [...openings.entries()]
            .filter(([, row]) => row.amount !== 0n)
            .map(([key, row]) => ({
              key,
              data: {
                fiscalYear: row.fiscalYear,
                accountCode: row.accountCode,
                amount: row.amount.toString(),
              },
            })),
        );
        openings.clear();
      }

      const items = buffers.get(earlier) ?? [];

      buffers.delete(earlier);

      for (let at = 0; at < items.length; at += size) {
        await write(earlier, items.slice(at, at + size));
      }
    }
  };

  const push = async (phase: Phase, item: AuditImportItem): Promise<void> => {
    await flushBefore(phase);

    const items = buffers.get(phase) ?? [];

    items.push(item);
    buffers.set(phase, items);

    if (items.length >= size) {
      buffers.delete(phase);
      await write(phase, items);
    }
  };

  const handle = async (record: AuditRecord): Promise<void> => {
    if (record.kind === "header") {
      header = record.header;
    } else if (record.kind === "warning") {
      warnings.push(record.warning);
    } else if (record.kind === "account") {
      const { account } = record;

      await push("account", {
        key: account.code,
        data: { code: account.code, name: account.name, type: account.type },
      });
    } else if (record.kind === "taxCode") {
      const { taxCode } = record;

      await push("taxCode", {
        key: taxCode.code,
        data: {
          code: taxCode.code,
          name: taxCode.description,
          type: taxCode.type,
          ...(taxCode.rateBps === undefined
            ? {}
            : { rateBps: taxCode.rateBps, validFrom: from }),
        },
      });
    } else if (record.kind === "party") {
      const { party } = record;

      if (entities.party === undefined) {
        partiesSkipped += 1;
      } else {
        await push("party", {
          key: party.code,
          scope: party.kind,
          data: {
            kind: party.kind,
            code: party.code,
            name: party.name,
            ...(party.taxId === undefined ? {} : { taxId: party.taxId }),
            ...(party.country === undefined ? {} : { country: party.country }),
            ...(party.accountCode === undefined
              ? {}
              : { accountCode: party.accountCode }),
          },
        });
      }
    } else if (record.kind === "journal") {
      const { journal } = record;

      await push("journal", {
        key: journal.code,
        data: { code: journal.code, name: journal.name, type: journal.type },
      });
    } else if (record.kind === "openingBalance") {
      const { balance } = record;
      const key = `${balance.fiscalYear}/${balance.accountCode}`;

      // The opening balance entity holds one row per account here, so rows per
      // customer or supplier add up to their account.
      if (balance.partyCode !== undefined) {
        merged.add(key);
      }

      const seen = openings.get(key);

      openings.set(key, {
        fiscalYear: balance.fiscalYear,
        accountCode: balance.accountCode,
        amount: (seen?.amount ?? 0n) + balance.amount,
      });
    } else {
      for (const line of record.entry.lines) {
        if (line.partyCode !== undefined) {
          partyLinks += 1;
        }

        if (line.taxCode !== undefined) {
          taxLinks += 1;
        }
      }

      await push("entry", entryItem(record.entry));
    }
  };

  try {
    for await (const record of adapter.parse(file, options.parse)) {
      await handle(record);
    }

    await flushBefore("entry");

    for (const phase of PHASES) {
      const items = buffers.get(phase) ?? [];

      for (let at = 0; at < items.length; at += size) {
        await write(phase, items.slice(at, at + size));
      }
    }
  } catch (error) {
    if (!(error instanceof PortFailure)) {
      throw error;
    }

    // The batches after a failed one would refer to rows that are missing.
    errors.push({
      entity: error.entity,
      key: null,
      code: "AUDIT_IMPORT_PORT_FAILED",
      message: error.message,
    });
  }

  if (partiesSkipped > 0) {
    warnings.push({
      code: "AUDIT_PARTY_NOT_IMPORTED",
      message: `${partiesSkipped} customers and suppliers were not imported: the accounting block has no entity for them; pass entities.party to import them`,
      count: partiesSkipped,
    });
  }

  if (partyLinks > 0) {
    warnings.push({
      code: "AUDIT_PARTY_LINK_DROPPED",
      message: `${partyLinks} entry lines name a customer or supplier; the link is not stored on the imported lines`,
      count: partyLinks,
    });
  }

  if (taxLinks > 0) {
    warnings.push({
      code: "AUDIT_TAX_CODE_NOT_IMPORTED",
      message: `${taxLinks} entry lines name a tax code; the code is not stored on the imported lines, only its amount`,
      count: taxLinks,
    });
  }

  if (merged.size > 0) {
    warnings.push({
      code: "AUDIT_OPENING_PARTY_MERGED",
      message: `opening balances of ${merged.size} accounts were split per customer or supplier; they were added up per account`,
      count: merged.size,
    });
  }

  return {
    header,
    counts: Object.fromEntries(counts),
    errors,
    warnings,
    ok: errors.length === 0,
  };
}
