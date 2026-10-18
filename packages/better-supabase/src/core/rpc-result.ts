import type {
  Codec,
  FunctionMeta,
  FunctionSignature,
  SchemaMeta,
} from "../schema/types.ts";
import type { RpcColumn } from "./executor.ts";

import { decodeValue } from "../ir/wire.ts";
import { lookupOf } from "../schema/lookup.ts";
import { isPlainObject } from "./clone.ts";

/** Database key to app key and codec, for the columns decoding changes. */
type Columns = ReadonlyMap<string, readonly [string, Codec | undefined]>;

const columnsByFunction = new WeakMap<FunctionMeta, Columns | null>();

function columnsOf(meta: SchemaMeta, fn: FunctionMeta): Columns | null {
  const cached = columnsByFunction.get(fn);

  if (cached !== undefined) {
    return cached;
  }

  let columns: Map<string, readonly [string, Codec | undefined]> | null = null;
  const { result } = fn;

  if (result && "table" in result) {
    const table = meta.tables[result.table];

    if (table) {
      columns = new Map();

      for (const [db, [app, column]] of lookupOf(table).byDb) {
        if (app !== db || column.codec) {
          columns.set(db, [app, column.codec]);
        }
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

const selectByFunction = new WeakMap<
  FunctionMeta,
  readonly RpcColumn[] | null
>();

/**
 * The columns `$rpc` selects for a function whose result has a codec column,
 * with that column cast to text as repository reads do. Undefined when no
 * result column has a codec, so the call selects everything.
 */
export function rpcSelect(
  meta: SchemaMeta,
  fn: FunctionMeta | undefined,
): readonly RpcColumn[] | undefined {
  if (!fn) {
    return undefined;
  }

  let select = selectByFunction.get(fn);

  if (select === undefined) {
    const { result } = fn;

    const table =
      result && "table" in result ? meta.tables[result.table] : undefined;

    const columns: readonly (readonly [string, Codec | undefined])[] = table
      ? [...lookupOf(table).byDb].map(([db, [, column]]) => [db, column.codec])
      : result && "columns" in result
        ? result.columns.map((column) => [column.db, column.codec])
        : [];

    select = columns.some(([, codec]) => codec)
      ? columns.map(([column, codec]) =>
          codec ? { column, cast: "text" } : { column },
        )
      : null;
    selectByFunction.set(fn, select);
  }

  return select ?? undefined;
}

function decodeRow(columns: Columns, row: unknown): unknown {
  if (!isPlainObject(row)) {
    return row;
  }

  const out: Record<string, unknown> = {};

  for (const key in row) {
    if (!Object.hasOwn(row, key)) {
      continue;
    }

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

const overloadMeta = new WeakMap<FunctionSignature, FunctionMeta>();

/**
 * The signature `$rpc` calls: PostgREST picks an overload by the argument
 * names, so a call matches the overload that has every name it passes and
 * every argument without a default. Undefined when the function is in
 * another schema or when no overload, or more than one, matches.
 */
export function rpcFunction(
  meta: SchemaMeta,
  name: string,
  schema: string,
  args: Readonly<Record<string, unknown>>,
): FunctionMeta | undefined {
  const fn = meta.functions[name];

  if (!fn || fn.schema !== schema) {
    return undefined;
  }

  if (!fn.overloads) {
    return fn;
  }

  const keys = Object.keys(args).filter((key) => args[key] !== undefined);

  const matches = fn.overloads.filter(
    (overload) =>
      keys.every((key) => overload.args.some((arg) => arg.name === key)) &&
      overload.args.every(
        (arg) => arg.optional === true || keys.includes(arg.name),
      ),
  );

  const [match] = matches;

  if (!match || matches.length > 1) {
    return undefined;
  }

  let resolved = overloadMeta.get(match);

  if (!resolved) {
    resolved = { ...match, name: fn.name, schema: fn.schema };
    overloadMeta.set(match, resolved);
  }

  return resolved;
}

/**
 * The `$rpc` result in app form: rows of a table or a `returns table (...)`
 * record get the configured casing and codecs, like repository reads.
 * Scalars, json and calls without a known signature come back unchanged.
 */
export function decodeRpcResult(
  meta: SchemaMeta,
  fn: FunctionMeta | undefined,
  data: unknown,
): unknown {
  if (!fn) {
    return data;
  }

  const columns = columnsOf(meta, fn);

  if (!columns || columns.size === 0) {
    return data;
  }

  return Array.isArray(data)
    ? data.map((row) => decodeRow(columns, row))
    : decodeRow(columns, data);
}
