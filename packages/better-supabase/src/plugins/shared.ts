import type { CallOptions } from "../core/plugin.ts";
import type { Condition, InsertOp, MutationOp } from "../ir/types.ts";
import type { TableMeta } from "../schema/types.ts";

import { dbError } from "../core/errors.ts";
import { DbException } from "../core/errors.ts";
import { lookupOf } from "../schema/lookup.ts";

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

/**
 * Refuses caller-supplied values for columns a plugin fills (timestamps,
 * actor, soft delete) unless the call passes `{ override: true }`. Returns
 * whether the caller may keep its own values.
 */
export function guardManaged(
  op: MutationOp,
  columns: readonly (string | undefined)[],
  plugin: string,
  options: CallOptions,
): boolean {
  if (options["override"] === true) return true;
  const rows =
    op.kind === "insert" ? op.rows : op.kind === "update" ? [op.set] : [];
  for (const column of columns) {
    if (column === undefined) continue;
    if (rows.some((row) => column in row)) {
      throw new DbException(
        dbError(
          "invalid_request",
          `"${column}" on ${op.table.key} is filled by ${plugin}(); pass { override: true } to set it yourself`,
          { table: op.table.key },
        ),
      );
    }
  }
  return false;
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
