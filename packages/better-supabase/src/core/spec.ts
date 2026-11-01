import type {
  AggregateArgs,
  AggregateResult,
  CountArgs,
  GetArgs,
  ListArgs,
  Payload,
} from "../ir/args.ts";
import type {
  AnyFunctions,
  AnyModels,
  SchemaMeta,
  TableKey,
  TableMeta,
} from "../schema/types.ts";
import type { BlockReadMap, BlockReadSpecs } from "./block-reads.ts";
import type {
  CursorPageArgs,
  FindExt,
  GetKey,
  OffsetPageArgs,
  OffsetRangeArgs,
  PageOf,
} from "./repository-types.ts";

import { builderFor } from "../ir/build.ts";
import { touchedTables } from "../ir/tables.ts";
import { tableMeta } from "../schema/define.ts";

export type ReadMethod = "list" | "page" | "get" | "count" | "aggregate";

const READ_METHODS: readonly ReadMethod[] = [
  "list",
  "page",
  "get",
  "count",
  "aggregate",
];

declare const resultType: unique symbol;

/**
 * A read, described as plain JSON: build it with `betterSupabase.spec`, run it
 * with `db.$run(spec)`, send it from a Server Component to the client, or hand
 * it to `/query` and `/next`. Args never carry a `signal`.
 */
export interface QuerySpec<
  T extends string = string,
  K extends ReadMethod = ReadMethod,
  R = unknown,
> {
  readonly v: 1;
  readonly table: T;
  readonly method: K;
  /** Positional arguments of the repository method. */
  readonly args: readonly unknown[];
  /** Type-only: the result `db.$run(spec)` resolves to. */
  readonly [resultType]?: R;
}

declare const functionResultType: unique symbol;

/**
 * A call of a SQL function the caller may execute, for a read set: build it
 * with `s.$fn.<name>(args)`. The function runs inside the set's own function,
 * as the caller, so RLS applies as it does for `db.$rpc`.
 */
export interface FunctionSpec<N extends string = string, R = unknown> {
  readonly v: 1;
  readonly kind: "function";
  readonly name: N;
  /** Named arguments; placeholders stand for read set parameters. */
  readonly args: Readonly<Record<string, unknown>>;
  /**
   * The tables the function reads, when known (a block read lists its module's
   * tables). `bsb.tags` tags a cache scope with them.
   */
  readonly tables?: readonly string[];
  /**
   * The schema the function lives in, when it is not one the schema metadata
   * lists (a block read names the block's API schema).
   */
  readonly schema?: string;
  /** Type-only: the result of the call. */
  readonly [functionResultType]?: R;
}

/** The function calls `s.$fn` offers: one per function in the schema. */
export type FunctionSpecs<F extends AnyFunctions> = {
  readonly [N in keyof F & string]: [F[N]["Args"]] extends [never]
    ? () => FunctionSpec<N, F[N]["Returns"]>
    : (args: F[N]["Args"]) => FunctionSpec<N, F[N]["Returns"]>;
};

/** What a read set entry holds: a table read or a function call. */
export type ReadSetEntry = QuerySpec | FunctionSpec;

/** The result of a read set entry. */
export type InferEntryResult<S> =
  S extends FunctionSpec<string, infer R> ? R : InferResult<S>;

/** What `record_summary` returns for a record the caller can read. */
export interface RecordSummaryRead {
  readonly type: string;
  readonly id: string;
  readonly title: string | null;
  readonly url: string | null;
  readonly counts: Readonly<Record<string, number>>;
  readonly unread: Readonly<Record<string, boolean>>;
}

/** The options of `s.record(type, id, options)`. */
export interface RecordReadOptions {
  /** The sections to count (`comments`, `attachments`); at most 20. */
  readonly sections?: readonly string[];
  /** When the caller last saw the record, as an ISO timestamp. */
  readonly seenAt?: string;
}

/**
 * The builders a read set gets: the table specs, `$fn`, `blocks` (the reads the
 * installed blocks ship) and `record` (the record summary).
 */
export type ReadSetSpecs<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  B extends BlockReadMap = Record<never, never>,
> = Specs<M, E> & {
  readonly $fn: FunctionSpecs<F>;
  readonly blocks: BlockReadSpecs<B>;
  record(
    type: string,
    id: string,
    options?: RecordReadOptions,
  ): FunctionSpec<"record_summary", RecordSummaryRead | null>;
};

/** The result type of a `QuerySpec`. */
export type InferResult<S> =
  S extends QuerySpec<string, ReadMethod, infer R> ? R : never;

type NoSignal<A> = Omit<A, "signal">;

export interface TableSpecs<M extends AnyModels, T extends TableKey<M>, E> {
  list<const A extends NoSignal<ListArgs<M, T>> & FindExt<E, M, T>>(
    args?: A,
  ): QuerySpec<T, "list", Payload<M, T, A>[]>;
  page<
    const A extends NoSignal<
      OffsetPageArgs<M, T> | OffsetRangeArgs<M, T> | CursorPageArgs<M, T>
    > &
      FindExt<E, M, T>,
  >(
    args: A,
  ): QuerySpec<T, "page", PageOf<M, T, A>>;
  get<const A extends NoSignal<GetArgs<M, T>> & FindExt<E, M, T>>(
    key: GetKey<M, T>,
    args?: A,
  ): QuerySpec<
    T,
    "get",
    A extends { readonly optional: true }
      ? Payload<M, T, A> | null
      : Payload<M, T, A>
  >;
  count(
    args?: NoSignal<CountArgs<M, T>> & FindExt<E, M, T>,
  ): QuerySpec<T, "count", number>;
  aggregate<const A extends NoSignal<AggregateArgs<M, T>> & FindExt<E, M, T>>(
    args: A,
  ): QuerySpec<T, "aggregate", AggregateResult<M, T, A>>;
}

export type Specs<M extends AnyModels, E> = {
  readonly [T in TableKey<M>]: TableSpecs<M, T, E>;
};

export function createSpecs(meta: SchemaMeta): Record<string, unknown> {
  const specs: Record<string, unknown> = {};

  for (const table of Object.keys(meta.tables)) {
    const methods: Record<string, unknown> = {};

    for (const method of READ_METHODS) {
      methods[method] = (...args: unknown[]): QuerySpec => ({
        v: 1,
        table,
        method,
        args: trimUndefined(args),
      });
    }

    specs[table] = methods;
  }

  return specs;
}

/** `s.record`: the record summary as a function entry. */
export function recordSpec(
  type: string,
  id: string,
  options: RecordReadOptions = {},
): FunctionSpec<"record_summary", RecordSummaryRead | null> {
  return {
    v: 1,
    kind: "function",
    name: "record_summary",
    args: {
      subject_type: type,
      subject_id: id,
      sections: [...(options.sections ?? [])],
      ...(options.seenAt === undefined ? {} : { seen_at: options.seenAt }),
    },
  };
}

/** `s.$fn`: any property is a builder; the read set checks the name. */
export function createFunctionSpecs(): Record<string, unknown> {
  return new Proxy(
    {},
    {
      get: (_target, name) =>
        typeof name === "string"
          ? (args?: Readonly<Record<string, unknown>>): FunctionSpec => ({
              v: 1,
              kind: "function",
              name,
              args: args ?? {},
            })
          : undefined,
    },
  );
}

export function isFunctionSpec(value: unknown): value is FunctionSpec {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  // SAFETY: value is a non-null object here, and every field is checked below.
  const spec = value as Partial<FunctionSpec>;

  return (
    spec.v === 1 &&
    spec.kind === "function" &&
    typeof spec.name === "string" &&
    typeof spec.args === "object"
  );
}

function trimUndefined(args: readonly unknown[]): unknown[] {
  const out = [...args];

  while (out.length > 0 && out.at(-1) === undefined) {
    out.pop();
  }

  return out;
}

export function isQuerySpec(value: unknown): value is QuerySpec {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  // SAFETY: value is a non-null object here, and every field is checked below.
  const spec = value as Partial<QuerySpec>;

  // includes only compares values, so a missing method is safe to look up.
  return (
    spec.v === 1 &&
    typeof spec.table === "string" &&
    READ_METHODS.includes(spec.method!) &&
    Array.isArray(spec.args)
  );
}

/**
 * The argument object of a spec's method. `get` takes it second, and its first
 * argument may be a `{ where }` filter.
 */
function specOptions(
  spec: QuerySpec,
): Readonly<Record<string, unknown>> | undefined {
  const value = spec.method === "get" ? spec.args[1] : spec.args[0];

  // SAFETY: value is a non-null object, the shape of a read method's options argument.
  const options =
    typeof value === "object" && value !== null
      ? (value as Record<string, unknown>)
      : undefined;

  const key = spec.method === "get" ? spec.args[0] : undefined;

  if (typeof key === "object" && key !== null && "where" in key) {
    return { ...options, where: key.where };
  }

  return options;
}

/**
 * App keys of every table a spec reads: its table, included relations and
 * relations used in `where`. Queries keyed by a spec go stale when any of them
 * changes. Invalid arguments yield just the spec's table; running the spec
 * reports the error.
 */
export function specTables(meta: SchemaMeta, spec: QuerySpec): string[] {
  const table = meta.tables[spec.table];
  const args = specOptions(spec);

  // Most specs read one table; skip building the query for them (this runs
  // on every render of a TanStack Query hook).
  if (
    table &&
    args?.["include"] === undefined &&
    !touchesRelations(table, args?.["where"])
  ) {
    return [spec.table];
  }

  const key = specKey(spec);
  let byKey = tablesByMeta.get(meta);

  if (!byKey) {
    byKey = new Map();
    tablesByMeta.set(meta, byKey);
  }

  const known = key === undefined ? undefined : byKey.get(key);

  if (known) {
    return [...known];
  }

  let tables: string[];

  try {
    tables = readTables(meta, spec);
  } catch {
    tables = [spec.table];
  }

  if (key !== undefined) {
    if (byKey.size >= SPEC_CACHE_SIZE) {
      byKey.clear();
    }

    byKey.set(key, tables);
  }

  return [...tables];
}

const SPEC_CACHE_SIZE = 500;
const tablesByMeta = new WeakMap<SchemaMeta, Map<string, readonly string[]>>();

/** A text key for the spec, or `undefined` when its arguments do not serialize. */
function specKey(spec: QuerySpec): string | undefined {
  try {
    return JSON.stringify(
      [spec.table, spec.method, spec.args],
      (_key, value: unknown) =>
        typeof value === "bigint" ? `${value}n` : value,
    );
  } catch {
    return undefined;
  }
}

function touchesRelations(table: TableMeta, where: unknown): boolean {
  if (typeof where !== "object" || where === null) {
    return false;
  }

  if (Array.isArray(where)) {
    return where.some((item) => touchesRelations(table, item));
  }

  for (const [key, value] of Object.entries(where)) {
    if (key in table.relations) {
      return true;
    }

    if (
      (key === "AND" || key === "OR" || key === "NOT") &&
      touchesRelations(table, value)
    ) {
      return true;
    }
  }

  return false;
}

function readTables(meta: SchemaMeta, spec: QuerySpec): string[] {
  const builder = builderFor(meta);
  const table = tableMeta(meta, spec.table);
  const args = specOptions(spec);

  const counts = spec.method === "count" || spec.method === "aggregate";

  return touchedTables({
    kind: "select",
    table,
    // SAFETY: isQuerySpec checked the method, and the select option of every
    // read method is a column list.
    selection: counts
      ? { columns: [], includes: [] }
      : builder.selection(
          table,
          args?.["select"] as readonly string[] | undefined,
          args?.["include"],
        ),
    where: builder.where(table, args?.["where"]),
    orderBy: [],
    limit: undefined,
    offset: undefined,
    count: undefined,
    head: counts,
    single: undefined,
  });
}
