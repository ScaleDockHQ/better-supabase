import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AsyncResult } from "../../core/result.ts";
import type { TableMeta } from "../../schema/types.ts";
import type { DryRunResult, ImportDefinition } from "./define-import.ts";

import { dryRun } from "./define-import.ts";

type Values = Readonly<Record<string, unknown>>;

/**
 * The repository methods an upsert import uses. A generated repository
 * (`db.tasks`) fits it.
 */
export interface AppTableImportRepository<
  T extends object,
  K extends Extract<keyof T, string>,
> {
  readonly $meta: TableMeta;
  list(args: {
    readonly where: { readonly OR: readonly Pick<T, K>[] };
  }): AsyncResult<readonly Values[]>;
  upsert(
    rows: readonly T[],
    args: { readonly onConflict: readonly K[]; readonly returning: false },
  ): AsyncResult<unknown>;
}

/**
 * How an import treats a row that already exists: `fill` writes only the fields
 * that are empty in the database, `overwrite` writes every field the file has.
 */
export type AppTableImportUpdate = "fill" | "overwrite";

export interface AppTableImportOptions<
  T extends object,
  K extends Extract<keyof T, string>,
> {
  /** The app table's name, the import's `kind`. */
  readonly table: string;
  readonly columns: StandardSchemaV1<unknown, T>;
  readonly repository: AppTableImportRepository<NoInfer<T>, NoInfer<K>>;
  /**
   * One of the table's unique sets (or its primary key) that finds an existing
   * row.
   */
  readonly key: readonly K[];
  /** Defaults to `fill`. */
  readonly update?: AppTableImportUpdate;
}

export interface ImportPreview {
  /** Rows the import inserts. */
  readonly created: number;
  /** Existing rows the import changes. */
  readonly changed: number;
  /** Existing rows the import leaves as they are. */
  readonly unchanged: number;
}

/**
 * An import that upserts into an app table; `runImport` and `previewImport`
 * take it.
 */
export interface AppTableImport<T extends object> extends ImportDefinition<T> {
  /** Counts the rows the import creates, changes and leaves; writes nothing. */
  readonly preview: (rows: readonly T[]) => Promise<ImportPreview>;
}

/**
 * An import that upserts rows into an app table on one of its unique sets. A
 * row whose key exists updates that row (see `update`); the rest are inserted.
 * Pass no `importedKeys` to `runImport`, so a rerun updates rows instead of
 * skipping them.
 */
export function appTableImport<
  T extends object,
  K extends Extract<keyof T, string>,
>(options: AppTableImportOptions<T, K>): AppTableImport<T> {
  const { repository, key } = options;
  const update = options.update ?? "fill";

  assertUniqueKey(options.table, repository.$meta, key);

  const keyOf = (row: object): string =>
    JSON.stringify(key.map((column) => valueOf(row, column) ?? null));

  const existing = async (
    rows: readonly T[],
  ): Promise<ReadonlyMap<string, Values>> => {
    if (rows.length === 0) {
      return new Map();
    }

    const found = await repository
      .list({ where: { OR: rows.map((row) => pick(row, key)) } })
      .orThrow();

    return new Map(found.map((row) => [keyOf(row), row]));
  };

  const merged = (row: T, current: Values | undefined): T =>
    current === undefined || update === "overwrite"
      ? row
      : {
          ...row,
          ...Object.fromEntries(
            Object.keys(row)
              .filter((column) => !isEmpty(current[column]))
              .map((column) => [column, current[column]]),
          ),
        };

  return {
    kind: options.table,
    columns: options.columns,
    key: keyOf,
    insert: async (batch) => {
      const found = await existing(batch);

      await repository
        .upsert(
          batch.map((row) => merged(row, found.get(keyOf(row)))),
          { onConflict: key, returning: false },
        )
        .orThrow();
    },
    preview: async (rows) => {
      const found = await existing(rows);
      let created = 0;
      let changed = 0;

      for (const row of rows) {
        const current = found.get(keyOf(row));

        if (current === undefined) {
          created += 1;
        } else if (differs(merged(row, current), current)) {
          changed += 1;
        }
      }

      return { created, changed, unchanged: rows.length - created - changed };
    },
  };
}

export interface PreviewImportResult<T> extends DryRunResult<T> {
  readonly preview: ImportPreview;
}

/**
 * Validates the file like `dryRun`, then counts the valid rows the import would
 * create, change and leave unchanged. Nothing is written.
 */
export async function previewImport<T extends object>(
  definition: AppTableImport<T>,
  csv: string,
  mapping: Readonly<Record<string, string>>,
): Promise<PreviewImportResult<T>> {
  const result = await dryRun(definition, csv, mapping);

  return { ...result, preview: await definition.preview(result.rows) };
}

function assertUniqueKey(
  table: string,
  meta: TableMeta,
  key: readonly string[],
): void {
  const sets = [meta.primaryKey, ...Object.values(meta.uniqueKeys)];
  const wanted = [...key].toSorted().join(",");

  if (
    key.length === 0 ||
    !sets.some((set) => [...set].toSorted().join(",") === wanted)
  ) {
    throw new Error(
      `appTableImport: key (${key.join(", ")}) is not a unique set of ${table}; add it to appTables.${table}.unique`,
    );
  }
}

function valueOf(row: object, column: string): unknown {
  return Object.getOwnPropertyDescriptor(row, column)?.value;
}

function pick<T extends object, K extends keyof T>(
  row: T,
  key: readonly K[],
): Pick<T, K> {
  const picked: Partial<Pick<T, K>> = {};

  for (const column of key) {
    picked[column] = row[column];
  }

  // SAFETY: the loop above set every key in `key`.
  return picked as Pick<T, K>;
}

function isEmpty(value: unknown): boolean {
  return value === null || value === undefined || value === "";
}

function differs(next: object, current: Values): boolean {
  return Object.entries(next).some(
    ([column, value]) =>
      JSON.stringify(value ?? null) !== JSON.stringify(current[column] ?? null),
  );
}
