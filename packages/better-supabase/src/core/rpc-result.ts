import type { Codec, FunctionMeta, SchemaMeta } from "../schema/types.ts";

import { decodeValue } from "../ir/wire.ts";
import { lookupOf } from "../schema/lookup.ts";
import { isPlainObject } from "./clone.ts";

/** Database key to app key and codec, for the columns decoding changes. */
type Columns = ReadonlyMap<string, readonly [string, Codec | undefined]>;

const columnsByFunction = new WeakMap<FunctionMeta, Columns | null>();

function columnsOf(meta: SchemaMeta, fn: FunctionMeta): Columns | null {
  const cached = columnsByFunction.get(fn);
  if (cached !== undefined) return cached;
  let columns: Map<string, readonly [string, Codec | undefined]> | null = null;
  const { result } = fn;
  if (result && "table" in result) {
    const table = meta.tables[result.table];
    if (table) {
      columns = new Map();
      for (const [db, [app, column]] of lookupOf(table).byDb) {
        if (app !== db || column.codec) columns.set(db, [app, column.codec]);
      }
    }
  } else if (result) {
    columns = new Map(
      result.columns.map((column) => [
        column.db,
        [column.name ?? column.db, column.codec],
      ]),
    );
  }
  columnsByFunction.set(fn, columns);
  return columns;
}

function decodeRow(columns: Columns, row: unknown): unknown {
  if (!isPlainObject(row)) return row;
  const out: Record<string, unknown> = {};
  for (const key in row) {
    if (!Object.hasOwn(row, key)) continue;
    const column = columns.get(key);
    if (!column) {
      out[key] = row[key];
      continue;
    }
    const [app, codec] = column;
    out[app] = codec ? decodeValue(codec, row[key]) : row[key];
  }
  return out;
}

/**
 * The `$rpc` result in app form: rows of a table or a `returns table (...)`
 * record get the configured casing and codecs, like repository reads.
 * Scalars, json and functions in another schema come back unchanged.
 */
export function decodeRpcResult(
  meta: SchemaMeta,
  name: string,
  schema: string,
  data: unknown,
): unknown {
  const fn = meta.functions[name];
  if (!fn || fn.schema !== schema) return data;
  const columns = columnsOf(meta, fn);
  if (!columns || columns.size === 0) return data;
  return Array.isArray(data)
    ? data.map((row) => decodeRow(columns, row))
    : decodeRow(columns, data);
}
