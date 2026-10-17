import type { StandardSchemaV1 } from "@standard-schema/spec";

import { parseCsv } from "../../core/csv.ts";
import { validate } from "../../core/standard.ts";

export interface ImportColumn {
  readonly name: string;
  readonly label?: string;
}

export interface ImportDefinition<T> {
  readonly kind: string;
  readonly columns: StandardSchemaV1<unknown, T>;
  /** Stable id of a row, so a rerun skips a row that already imported. */
  readonly key: (row: T) => string;
  readonly insert: (
    batch: readonly T[],
    ctx: { readonly organizationId: string },
  ) => Promise<void>;
}

export interface ImportRowError {
  readonly row: number;
  readonly message: string;
}

export interface DryRunResult<T> {
  readonly rows: readonly T[];
  readonly errors: readonly ImportRowError[];
}

/** Registers an import. The jobs handler calls `insert` in batches. */
export function defineImport<T>(
  definition: ImportDefinition<T>,
): ImportDefinition<T> {
  return definition;
}

/**
 * Pairs CSV headers with import fields. A header matches a field when they
 * are equal after lowercasing and dropping spaces and underscores.
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
 * Parses CSV, applies `mapping` (CSV header to field name) and validates
 * every row. Nothing is written.
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
      `${definition.kind} row ${index + 2}`,
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

export interface RunImportResult<T> {
  readonly id: string;
  readonly status: "completed" | "failed";
  readonly imported: number;
  readonly errors: readonly ImportRowError[];
  readonly rows: readonly T[];
}

/**
 * Validates the file, skips rows whose key was already imported, inserts the
 * rest in batches and finishes the run as `import.completed` or `import.failed`.
 */
export async function runImport<T>(
  definition: ImportDefinition<T>,
  csv: string,
  mapping: Readonly<Record<string, string>>,
  hooks: {
    readonly organizationId: string;
    readonly importedKeys?: ReadonlySet<string>;
    readonly start: () => Promise<string>;
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

  for (let index = 0; index < fresh.length; index += BATCH) {
    await definition.insert(fresh.slice(index, index + BATCH), {
      organizationId: hooks.organizationId,
    });
  }

  await hooks.finish(id, "completed", fresh.length, null);

  return {
    id,
    status: "completed",
    imported: fresh.length,
    errors: [],
    rows: fresh,
  };
}

function normalize(value: string): string {
  return value.toLowerCase().replaceAll(/[\s_]+/g, "");
}
