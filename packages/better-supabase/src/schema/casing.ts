import type { TableMeta } from "./types.ts";

import { lookupOf } from "./lookup.ts";

type Row = Readonly<Record<string, unknown>>;

/** Database-keyed row to app-keyed row. */
export function toApp(table: TableMeta, row: Row): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [app, meta] of lookupOf(table).entries) {
    if (meta.db in row) out[app] = row[meta.db];
  }
  return out;
}

/** App-keyed row to database-keyed row. Unknown keys are dropped. */
export function toDb(table: TableMeta, row: Row): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [app, meta] of lookupOf(table).entries) {
    if (app in row) out[meta.db] = row[app];
  }
  return out;
}
