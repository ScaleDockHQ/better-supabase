import type { Condition, SelectOp } from "../ir/types.ts";

import { listItem, type PostgrestPlan } from "../compile/postgrest.ts";
import { lookupOf } from "../schema/lookup.ts";
import { type DbError, dbError } from "./errors.ts";

type Row = Record<string, unknown>;
type InCondition = Extract<Condition, { kind: "column" }> & {
  readonly value: readonly unknown[];
};

/** The length of the query string supabase-js sends for `plan`. */
export function queryLength(plan: PostgrestPlan): number {
  let length = plan.select === undefined ? 0 : 8 + encoded(plan.select);
  for (const filter of plan.filters) {
    length +=
      filter.kind === "filter"
        ? encoded(filter.path) +
          2 +
          encoded(`${filter.operator}.${filter.value}`)
        : 4 +
          encoded(`(${filter.expression})`) +
          (filter.referencedTable ? encoded(filter.referencedTable) + 1 : 0);
  }
  for (const order of plan.orders) length += 24 + encoded(order.column);
  return length;
}

function encoded(text: string): number {
  return encodeURIComponent(text).length;
}

function topLevel(where: Condition | undefined): readonly Condition[] {
  if (!where) return [];
  return where.kind === "and" ? where.items : [where];
}

function isInList(condition: Condition): condition is InCondition {
  return (
    condition.kind === "column" &&
    condition.op === "in" &&
    condition.path === undefined &&
    Array.isArray(condition.value)
  );
}

/** Column types whose order JavaScript reproduces without the database's collation. */
const SORTABLE = new Set([
  "int2",
  "int4",
  "int8",
  "float4",
  "float8",
  "numeric",
  "uuid",
  "date",
  "timestamp",
  "timestamptz",
  "bool",
]);
const NUMERIC = new Set([
  "int2",
  "int4",
  "int8",
  "float4",
  "float8",
  "numeric",
]);

function tooLong(
  op: SelectOp,
  length: number,
  max: number,
  why: string,
): DbError {
  return dbError(
    "invalid_request",
    `The request for "${op.table.key}" is ${length} characters, over the ${max} the URL takes, and ${why}`,
    {
      table: op.table.key,
      hint: "Split the in list or paginate, or pass a shorter list to a search function.",
    },
  );
}

export interface ChunkedRead {
  readonly ops: readonly SelectOp[];
  /** Sorts the merged rows like the database would, when the read has an order. */
  readonly sort: ((rows: Row[]) => Row[]) | undefined;
}

/**
 * Splits a read whose query string is over `max` into reads that each fit,
 * along its longest top-level `in` list. Only reads without a limit, offset,
 * count or single row qualify, since chunks can't share those; their rows are
 * disjoint, and an order is re-applied in memory on columns that sort the
 * same in JavaScript.
 */
export function chunkRead(
  op: SelectOp,
  plan: PostgrestPlan,
  max: number,
): ChunkedRead | DbError {
  const length = queryLength(plan);
  if (
    op.limit !== undefined ||
    op.offset !== undefined ||
    op.count !== undefined ||
    op.head ||
    op.single !== undefined ||
    op.source !== undefined
  ) {
    return tooLong(
      op,
      length,
      max,
      "a read with a limit, offset, count or single row can't be split",
    );
  }
  const items = topLevel(op.where);
  const lists = items.filter(isInList);
  const longest = lists
    .map((condition) => ({
      condition,
      sizes: condition.value.map((value) => encoded(listItem(value)) + 3),
    }))
    .sort(
      (a, b) =>
        b.sizes.reduce((sum, size) => sum + size, 0) -
        a.sizes.reduce((sum, size) => sum + size, 0),
    )[0];
  if (!longest)
    return tooLong(op, length, max, "it has no top-level in list to split");
  const listLength = longest.sizes.reduce((sum, size) => sum + size, 0);
  const budget = max - (length - listLength);
  if (budget < Math.max(...longest.sizes)) {
    return tooLong(
      op,
      length,
      max,
      "the rest of the request leaves no room for its in list",
    );
  }

  let sort: ChunkedRead["sort"];
  if (op.orderBy.length > 0) {
    const { byDb } = lookupOf(op.table);
    const aliases = new Map(
      op.selection.columns.map((c) => [c.column, c.alias]),
    );
    const keys: {
      alias: string;
      desc: boolean;
      nullsFirst: boolean;
      numeric: boolean;
    }[] = [];
    for (const term of op.orderBy) {
      const type = byDb.get(term.column)?.[1].type ?? "";
      const alias = aliases.get(term.column);
      if (term.relation || alias === undefined || !SORTABLE.has(type)) {
        return tooLong(
          op,
          length,
          max,
          `its order on "${term.column}" can't be re-applied after splitting it; order by selected number, uuid, date or time columns`,
        );
      }
      const desc = term.direction === "desc";
      keys.push({
        alias,
        desc,
        nullsFirst: (term.nulls ?? (desc ? "first" : "last")) === "first",
        numeric: NUMERIC.has(type),
      });
    }
    sort = (rows) =>
      rows.sort((left, right) => {
        for (const key of keys) {
          const a = left[key.alias];
          const b = right[key.alias];
          if (a === b) continue;
          if (a === null || a === undefined) return key.nullsFirst ? -1 : 1;
          if (b === null || b === undefined) return key.nullsFirst ? 1 : -1;
          const order = key.numeric
            ? Number(a) - Number(b)
            : String(a) < String(b)
              ? -1
              : String(a) > String(b)
                ? 1
                : 0;
          if (order !== 0) return key.desc ? -order : order;
        }
        return 0;
      });
  }

  const chunks: unknown[][] = [];
  let current: unknown[] = [];
  let used = 0;
  longest.condition.value.forEach((value, index) => {
    const size = longest.sizes[index] ?? 0;
    if (current.length > 0 && used + size > budget) {
      chunks.push(current);
      current = [];
      used = 0;
    }
    current.push(value);
    used += size;
  });
  if (current.length > 0) chunks.push(current);

  const ops = chunks.map((values): SelectOp => {
    const where = items.map((item) =>
      item === longest.condition
        ? { ...longest.condition, value: values }
        : item,
    );
    return {
      ...op,
      where: where.length === 1 ? where[0] : { kind: "and", items: where },
    };
  });
  return { ops, sort };
}
