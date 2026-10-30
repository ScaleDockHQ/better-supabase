import type { StandardSchemaV1 } from "@standard-schema/spec";

import { parseCsv } from "../../core/csv.ts";
import { validate } from "../../core/standard.ts";

export interface ImportColumn {
  readonly name: string;
  readonly label?: string;
}

/** One item of an `upsertBatch` call (ADR 0141). */
export interface ImportItem {
  /** The record's key in the source system. */
  readonly key: string;
  /**
   * The key's namespace in the source, such as a company; `''` when it has
   * none.
   */
  readonly scope?: string;
  /** What the target writes. Its hash decides insert, unchanged or changed. */
  readonly data: Readonly<Record<string, unknown>>;
  /** Keys of other imported records this one points at, by entity. */
  readonly refs?: Readonly<Record<string, string>>;
}

/** The outcome counts of one batch or one entity of a run. */
export interface ImportBatchCounts {
  readonly inserted: number;
  readonly updated: number;
  readonly unchanged: number;
  readonly conflicted: number;
}

export interface ImportDefinition<T> {
  /**
   * The source system the run reads from; one run per tenant and source is
   * active.
   */
  readonly source: string;
  readonly columns: StandardSchemaV1<unknown, T>;
  /** Stable id of a row, so a rerun skips a row that already imported. */
  readonly key: (row: T) => string;
  /**
   * The legacy writer. Without `target` it writes each batch itself; with a
   * `target`, `runImport` sends the rows through `hooks.upsertBatch` instead.
   */
  readonly insert?: (
    batch: readonly T[],
    ctx: { readonly organizationId: string },
  ) => Promise<void>;
  /**
   * Writes through the external record map: the entity (an `importTarget`) and
   * how a row becomes an item. A rerun then updates or skips what imported.
   */
  readonly target?: {
    readonly entity: string;
    readonly item: (
      row: T,
    ) => Omit<ImportItem, "key"> & Partial<Pick<ImportItem, "key">>;
  };
}

export interface ImportRowError {
  readonly row: number;
  readonly message: string;
}

export interface DryRunResult<T> {
  readonly rows: readonly T[];
  readonly errors: readonly ImportRowError[];
}

/** Registers an import. `runImport` calls `insert` in batches. */
export function defineImport<T>(
  definition: ImportDefinition<T>,
): ImportDefinition<T> {
  if (definition.insert === undefined && definition.target === undefined) {
    throw new TypeError(
      `import "${definition.source}" needs an insert function or a target`,
    );
  }

  return definition;
}

/**
 * Pairs CSV headers with import fields. A header matches a field when they are
 * equal after lowercasing and dropping spaces and underscores.
 */
export function suggestMapping(
  headers: readonly string[],
  fields: readonly string[],
): Readonly<Record<string, string | undefined>> {
  const byKey = new Map(fields.map((field) => [normalize(field), field]));
  const mapping: Record<string, string | undefined> = {};

  for (const header of headers) {
    mapping[header] = byKey.get(normalize(header));
  }

  return mapping;
}

/**
 * Parses CSV, applies `mapping` (CSV header to field name) and validates every
 * row. Nothing is written.
 */
export async function dryRun<T>(
  definition: ImportDefinition<T>,
  csv: string,
  mapping: Readonly<Record<string, string>>,
): Promise<DryRunResult<T>> {
  const table = parseCsv(csv);
  const [header, ...body] = table;

  if (header === undefined) {
    return { rows: [], errors: [] };
  }

  const rows: T[] = [];
  const errors: ImportRowError[] = [];

  for (const [index, cells] of body.entries()) {
    const record: Record<string, string> = {};

    for (const [column, cell] of cells.entries()) {
      const name = mapping[header[column] ?? ""];

      if (name !== undefined) {
        record[name] = cell;
      }
    }

    const parsed = await validate(
      definition.columns,
      record,
      `${definition.source} row ${index + 2}`,
    );

    if (parsed.ok) {
      rows.push(parsed.data);
    } else {
      errors.push({ row: index + 2, message: parsed.error.message });
    }
  }

  return { rows, errors };
}

const BATCH = 100;

/** What `import_upsert_batch` answers for one batch. */
export interface ImportBatchReply extends ImportBatchCounts {
  readonly errors: readonly {
    readonly key: string | null;
    readonly code: string;
    readonly message: string;
  }[];
}

export interface RunImportResult<T> {
  readonly id: string;
  readonly status: "completed" | "failed";
  readonly imported: number;
  readonly errors: readonly ImportRowError[];
  readonly rows: readonly T[];
  /** Per outcome, for a run that wrote through `target`. */
  readonly counts?: ImportBatchCounts;
}

/**
 * Validates the file, skips rows whose key was already imported, inserts the
 * rest in batches and finishes the run as `import.completed` or
 * `import.failed`. A batch that throws finishes the run as failed with the rows
 * inserted so far, and the result says so instead of the error escaping.
 */
export async function runImport<T>(
  definition: ImportDefinition<T>,
  csv: string,
  mapping: Readonly<Record<string, string>>,
  hooks: {
    readonly organizationId: string;
    readonly importedKeys?: ReadonlySet<string>;
    readonly start: () => Promise<string>;
    /** Writes a batch through `import_upsert_batch`; needed with `target`. */
    readonly upsertBatch?: (
      entity: string,
      items: readonly ImportItem[],
    ) => Promise<ImportBatchReply>;
    /** Marks the run `running` before the first batch (`mark_import_running`). */
    readonly running?: (id: string) => Promise<void>;
    readonly finish: (
      id: string,
      status: "completed" | "failed",
      count: number,
      error: string | null,
    ) => Promise<void>;
  },
): Promise<RunImportResult<T>> {
  const preview = await dryRun(definition, csv, mapping);
  const id = await hooks.start();

  if (preview.errors.length > 0) {
    const error = preview.errors
      .map((item) => `row ${item.row}: ${item.message}`)
      .join("; ");

    await hooks.finish(id, "failed", 0, error);

    return {
      id,
      status: "failed",
      imported: 0,
      errors: preview.errors,
      rows: [],
    };
  }

  const seen = new Set(hooks.importedKeys);

  const fresh = preview.rows.filter((row) => {
    const key = definition.key(row);

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);

    return true;
  });

  await hooks.running?.(id);
  let inserted = 0;
  const totals = { inserted: 0, updated: 0, unchanged: 0, conflicted: 0 };

  for (let index = 0; index < fresh.length; index += BATCH) {
    const batch = fresh.slice(index, index + BATCH);

    try {
      if (definition.target === undefined) {
        await definition.insert?.(batch, {
          organizationId: hooks.organizationId,
        });
      } else {
        const { entity, item } = definition.target;

        if (hooks.upsertBatch === undefined) {
          throw new TypeError(
            `import "${definition.source}" has a target, so runImport needs hooks.upsertBatch`,
          );
        }

        const reply = await hooks.upsertBatch(
          entity,
          batch.map((row) => ({
            ...item(row),
            key: item(row).key ?? definition.key(row),
          })),
        );

        totals.inserted += reply.inserted;
        totals.updated += reply.updated;
        totals.unchanged += reply.unchanged;
        totals.conflicted += reply.conflicted;

        if (reply.errors.length > 0) {
          throw new Error(
            reply.errors
              .map((item) => `${item.key ?? "item"}: ${item.message}`)
              .join("; "),
          );
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const first = index + 1;

      await hooks.finish(id, "failed", inserted, message);

      return {
        id,
        status: "failed",
        imported: inserted,
        errors: [
          {
            row: first,
            message: `the batch starting at imported row ${first} failed: ${message}`,
          },
        ],
        rows: fresh.slice(0, inserted),
      };
    }

    inserted += batch.length;
  }

  await hooks.finish(id, "completed", fresh.length, null);

  return {
    id,
    status: "completed",
    imported: fresh.length,
    errors: [],
    rows: fresh,
    ...(definition.target === undefined ? {} : { counts: totals }),
  };
}

function normalize(value: string): string {
  return value.toLowerCase().replaceAll(/[\s_]+/g, "");
}
