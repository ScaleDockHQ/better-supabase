import type { Condition, InsertOp } from "../ir/types.ts";
import type { TableMeta } from "../schema/types.ts";

import { dbError } from "../core/errors.ts";
import { DbException } from "../core/errors.ts";

type Row = Readonly<Record<string, unknown>>;

/** Database column name for an app column, or `undefined` if it is unknown. */
export function dbName(
  table: TableMeta,
  app: string | undefined,
): string | undefined {
  return app === undefined ? undefined : table.columns[app]?.db;
}

export function isNull(column: string): Condition {
  return { kind: "column", column, op: "is", value: null };
}

export function isNotNull(column: string): Condition {
  return { kind: "not", item: isNull(column) };
}

export function equals(column: string, value: unknown): Condition {
  return { kind: "column", column, op: "eq", value };
}

/** Sets `column` on a row unless the caller already provided it. */
export function withDefault(
  row: Row,
  column: string | undefined,
  value: unknown,
): Row {
  if (column === undefined || column in row) return row;
  return { ...row, [column]: value };
}

/** Upserts that may update existing rows must not overwrite "created" columns. */
export function insertsOnly(op: InsertOp): boolean {
  return !op.onConflict || op.onConflict.action === "ignore";
}

export function forbidden(message: string): never {
  throw new DbException(dbError("forbidden", message));
}

/** Database-keyed row to app-keyed row. */
export function toApp(table: TableMeta, row: Row): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [app, meta] of Object.entries(table.columns)) {
    if (meta.db in row) out[app] = row[meta.db];
  }
  return out;
}

/** App-keyed row to database-keyed row. Unknown keys are dropped. */
export function toDb(table: TableMeta, row: Row): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [app, meta] of Object.entries(table.columns)) {
    if (app in row) out[meta.db] = row[app];
  }
  return out;
}
