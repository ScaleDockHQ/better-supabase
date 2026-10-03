import type { ColumnMeta, TableMeta } from "./types.ts";

/** Facts derived once per table from its generated metadata. */
export interface TableLookup {
  /** `[appName, column]` for every column, in metadata order. */
  readonly entries: readonly (readonly [string, ColumnMeta])[];
  /** Database name to `[appName, column]`. */
  readonly byDb: ReadonlyMap<string, readonly [string, ColumnMeta]>;
  /** The primary key, then every named unique key (app names). */
  readonly keys: readonly (readonly string[])[];
}

const lookups = new WeakMap<TableMeta, TableLookup>();

/** The cached lookup for a table; metadata is immutable after `defineSchema`. */
export function lookupOf(table: TableMeta): TableLookup {
  let lookup = lookups.get(table);
  if (!lookup) {
    const entries = Object.entries(table.columns);
    lookup = {
      entries,
      byDb: new Map(entries.map((entry) => [entry[1].db, entry])),
      keys: [table.primaryKey, ...Object.values(table.uniqueKeys)],
    };
    lookups.set(table, lookup);
  }
  return lookup;
}
