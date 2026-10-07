import type { Condition, MutationOp } from "../ir/types.ts";
import type { TableMeta } from "../schema/types.ts";

import { lookupOf } from "../schema/lookup.ts";

type Row = Record<string, unknown>;

/** App-cased primary keys of `rows`, or of a `where` that pins the primary key. */
export function keysOf(
  op: MutationOp,
  rows: readonly Row[],
): readonly Row[] | undefined {
  const { primaryKey } = op.table;
  if (primaryKey.length === 0) return undefined;
  const fromRows = rows.flatMap((row) =>
    primaryKey.every((name) => row[name] !== undefined && row[name] !== null)
      ? [Object.fromEntries(primaryKey.map((name) => [name, row[name]]))]
      : [],
  );
  if (fromRows.length > 0) return fromRows;
  if (op.kind === "insert") return undefined;
  return keysFromWhere(op.table, op.where);
}

function keysFromWhere(
  table: TableMeta,
  where: Condition | undefined,
): readonly Row[] | undefined {
  if (!where) return undefined;
  const { byDb } = lookupOf(table);
  const pinned = new Map<string, readonly unknown[]>();
  const items: Condition[] = [];
  const flatten = (condition: Condition): void => {
    if (condition.kind === "and") condition.items.forEach(flatten);
    else items.push(condition);
  };
  flatten(where);
  for (const item of items) {
    if (item.kind !== "column" || item.path) continue;
    const app = byDb.get(item.column)?.[0];
    if (app === undefined || !table.primaryKey.includes(app)) continue;
    if (item.op === "eq") pinned.set(app, [item.value]);
    else if (item.op === "in" && Array.isArray(item.value))
      pinned.set(app, item.value);
  }
  if (pinned.size !== table.primaryKey.length) return undefined;
  const [first, ...rest] = table.primaryKey;
  if (first === undefined) return undefined;
  if (rest.length === 0)
    return (pinned.get(first) ?? []).map((value) => ({ [first]: value }));
  if ([...pinned.values()].some((values) => values.length !== 1))
    return undefined;
  return [
    Object.fromEntries(
      table.primaryKey.map((name) => [name, pinned.get(name)?.[0]]),
    ),
  ];
}

/**
 * Rows in conflict-key order, so concurrent upserts lock the same rows in
 * the same order instead of deadlocking.
 */
export function byKey(
  rows: readonly Readonly<Record<string, unknown>>[],
  columns: readonly string[],
): Readonly<Record<string, unknown>>[] {
  const compare = (left: unknown, right: unknown): number => {
    if (left === right) return 0;
    if (left === null || left === undefined) return 1;
    if (right === null || right === undefined) return -1;
    if (typeof left === "number" && typeof right === "number")
      return left - right;
    if (typeof left === "bigint" && typeof right === "bigint")
      return left < right ? -1 : 1;
    const a = String(left);
    const b = String(right);
    return a < b ? -1 : a > b ? 1 : 0;
  };
  // Keys are read once per row, not once per comparison.
  const keyed = rows.map((row) => ({
    row,
    key: columns.map((column) => {
      const value = row[column];
      return typeof value === "object" && value !== null
        ? String(value)
        : value;
    }),
  }));
  keyed.sort((left, right) => {
    for (let index = 0; index < columns.length; index++) {
      const order = compare(left.key[index], right.key[index]);
      if (order !== 0) return order;
    }
    return 0;
  });
  return keyed.map((entry) => entry.row);
}
