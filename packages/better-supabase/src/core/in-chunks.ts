import type {
  Condition,
  Operation,
  SelectColumn,
  SelectOp,
} from "../ir/types.ts";

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
const TIME = new Set(["date", "timestamp", "timestamptz"]);
const NUMERIC = new Set(["int2", "int4", "float4", "float8", "numeric"]);

type SortKind = "number" | "bigint" | "time" | "text";

const INTEGER = /^-?\d+$/;

function sortKind(type: string): SortKind {
  if (type === "int8") return "bigint";
  if (NUMERIC.has(type)) return "number";
  return TIME.has(type) ? "time" : "text";
}

/** The `invalid_request` for a request whose URL is over the limit. */
export function tooLong(
  op: Operation,
  length: number,
  max: number,
  why: string,
): DbError {
  return dbError(
    "invalid_request",
    `The request for "${op.table.key}" is ${length} characters, over the ${max} the URL takes, and ${why}`,
    {
      table: op.table.key,
      hint: "Split the in list or paginate, pass a shorter list to a search function, or raise `urlLengthLimit` when every proxy in front of PostgREST accepts longer URLs.",
    },
  );
}

export interface ChunkedRead {
  readonly ops: readonly SelectOp[];
  /** Each op's plan, patched from the read's plan instead of compiled again. */
  readonly plans: readonly PostgrestPlan[] | undefined;
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
  let longest:
    | {
        condition: InCondition;
        values: unknown[];
        texts: string[];
        sizes: number[];
        total: number;
        largest: number;
      }
    | undefined;
  for (const condition of items) {
    if (!isInList(condition)) continue;
    // A value repeated across two chunks would return its rows twice.
    const seen = new Set<string>();
    const values: unknown[] = [];
    const texts: string[] = [];
    const sizes: number[] = [];
    let total = 0;
    let largest = 0;
    for (const value of condition.value) {
      const text = listItem(value);
      if (seen.has(text)) continue;
      seen.add(text);
      // `encodeURIComponent(",")` is three characters.
      const size = encoded(text) + 3;
      values.push(value);
      texts.push(text);
      sizes.push(size);
      total += size;
      if (size > largest) largest = size;
    }
    if (!longest || total > longest.total)
      longest = { condition, values, texts, sizes, total, largest };
  }
  if (!longest)
    return tooLong(op, length, max, "it has no top-level in list to split");
  const listLength = encoded(
    `(${longest.condition.value.map(listItem).join(",")})`,
  );

  // Order columns the read doesn't select are selected under a hidden alias
  // for the in-memory sort, then removed from the rows.
  // int8 columns come back as text, so values past 2^53 keep their order.
  const { byDb } = lookupOf(op.table);
  const hidden: SelectColumn[] = [];
  const aliases = new Map(op.selection.columns.map((c) => [c.column, c.alias]));
  for (const term of op.orderBy) {
    if (term.relation || aliases.has(term.column)) continue;
    const alias = `_bs_order${hidden.length}`;
    const exact = byDb.get(term.column)?.[1].type === "int8";
    hidden.push({
      alias,
      column: term.column,
      ...(exact ? { cast: "text" as const } : {}),
    });
    aliases.set(term.column, alias);
  }
  const hiddenText = (column: SelectColumn): string =>
    `${column.alias}:${column.column}${column.cast ? `::${column.cast}` : ""}`;
  const extra = hidden.reduce(
    (sum, column) => sum + encoded(`,${hiddenText(column)}`),
    0,
  );
  const budget = max - (length - listLength) - extra - encoded("()");
  if (budget < longest.largest) {
    return tooLong(
      op,
      length,
      max,
      "the rest of the request leaves no room for its in list",
    );
  }

  let sort: ChunkedRead["sort"];
  if (op.orderBy.length > 0) {
    const keys: {
      alias: string;
      desc: boolean;
      nullsFirst: boolean;
      kind: SortKind;
    }[] = [];
    for (const term of op.orderBy) {
      const type = byDb.get(term.column)?.[1].type ?? "";
      const alias = aliases.get(term.column);
      // The caller never asked for an implicit order, so sorting it by code
      // point instead of the database's collation is good enough.
      if (
        term.relation ||
        alias === undefined ||
        (!SORTABLE.has(type) && !term.implicit)
      ) {
        return tooLong(
          op,
          length,
          max,
          `its order on "${term.column}" can't be re-applied after splitting it; order by number, uuid, date or time columns`,
        );
      }
      const desc = term.direction === "desc";
      keys.push({
        alias,
        desc,
        nullsFirst: (term.nulls ?? (desc ? "first" : "last")) === "first",
        kind: sortKind(type),
      });
    }
    sort = (rows) => {
      // Sort keys are read once per row, not once per comparison.
      const decorated = rows.map((row) => ({
        row,
        values: keys.map((key) => sortValue(row[key.alias], key.kind)),
      }));
      decorated.sort((left, right) => {
        for (const [index, key] of keys.entries()) {
          const a = left.values[index];
          const b = right.values[index];
          if (a === b) continue;
          if (a === undefined) return key.nullsFirst ? -1 : 1;
          if (b === undefined) return key.nullsFirst ? 1 : -1;
          const order = a < b ? -1 : a > b ? 1 : 0;
          if (order !== 0) return key.desc ? -order : order;
        }
        return 0;
      });
      return decorated.map(({ row }) => {
        for (const column of hidden) delete row[column.alias];
        return row;
      });
    };
  }

  const chunks: { values: unknown[]; texts: string[] }[] = [];
  let current: { values: unknown[]; texts: string[] } = {
    values: [],
    texts: [],
  };
  let used = 0;
  const list = longest;
  list.values.forEach((value, index) => {
    const size = list.sizes[index] ?? 0;
    if (current.values.length > 0 && used + size > budget) {
      chunks.push(current);
      current = { values: [], texts: [] };
      used = 0;
    }
    current.values.push(value);
    current.texts.push(list.texts[index] ?? "");
    used += size;
  });
  if (current.values.length > 0) chunks.push(current);

  const full = `(${list.condition.value.map(listItem).join(",")})`;
  const at = plan.filters.findIndex(
    (filter) =>
      filter.kind === "filter" &&
      filter.operator === "in" &&
      filter.path === list.condition.column &&
      filter.value === full,
  );
  const select =
    plan.select === undefined || hidden.length === 0
      ? plan.select
      : `${plan.select},${hidden.map(hiddenText).join(",")}`;
  const plans =
    at === -1
      ? undefined
      : chunks.map((chunk): PostgrestPlan => ({
          ...plan,
          select,
          filters: plan.filters.map((filter, index) =>
            index === at && filter.kind === "filter"
              ? { ...filter, value: `(${chunk.texts.join(",")})` }
              : filter,
          ),
        }));

  const ops = chunks.map(({ values }): SelectOp => {
    const where = items.map((item) =>
      item === list.condition ? { ...list.condition, value: values } : item,
    );
    return {
      ...op,
      ...(hidden.length > 0 && {
        selection: {
          ...op.selection,
          columns: [...op.selection.columns, ...hidden],
        },
      }),
      where: where.length === 1 ? where[0] : { kind: "and", items: where },
    };
  });
  return { ops, plans, sort };
}

/**
 * A comparable value, or `undefined` for SQL null. Times compare by
 * instant, which text can't do across offsets, with the microseconds
 * `Date.parse` drops appended.
 */
function sortValue(
  value: unknown,
  kind: SortKind,
): number | bigint | string | undefined {
  if (value === null || value === undefined) return undefined;
  if (kind === "number") return Number(value);
  if (kind === "bigint") {
    if (typeof value === "bigint") return value;
    if (typeof value === "number" && Number.isInteger(value))
      return BigInt(value);
    if (typeof value === "string" && INTEGER.test(value)) return BigInt(value);
    return Number(value);
  }
  const text = String(value);
  if (kind === "text") return text;
  const instant = Date.parse(text);
  if (Number.isNaN(instant)) return text;
  const fraction = /\.(\d+)/.exec(text)?.[1] ?? "";
  const micros = fraction.slice(3, 6).padEnd(3, "0");
  return `${String(instant + 8.64e15).padStart(17, "0")}${micros}`;
}
