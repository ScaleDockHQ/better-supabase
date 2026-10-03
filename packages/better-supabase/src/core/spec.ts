import type {
  AggregateArgs,
  AggregateResult,
  CountArgs,
  FindFirstArgs,
  FindManyArgs,
  Payload,
  ReadArgs,
  WhereInput,
} from "../ir/args.ts";
import type {
  AnyModels,
  PrimaryKeyValue,
  SchemaMeta,
  TableKey,
  UniqueWhere,
} from "../schema/types.ts";
import type {
  CursorPageArgs,
  FindExt,
  OffsetPageArgs,
  PageOf,
} from "./repository-types.ts";

import { IrBuilder } from "../ir/build.ts";
import { touchedTables } from "../ir/tables.ts";
import { tableMeta } from "../schema/define.ts";

export type ReadMethod =
  | "findMany"
  | "findFirst"
  | "findUnique"
  | "findById"
  | "count"
  | "aggregate"
  | "exists"
  | "paginate";

const READ_METHODS: readonly ReadMethod[] = [
  "findMany",
  "findFirst",
  "findUnique",
  "findById",
  "count",
  "aggregate",
  "exists",
  "paginate",
];

declare const resultType: unique symbol;

/**
 * A read, described as plain JSON: build it with `betterSupabase.spec`, run it with
 * `db.$run(spec)`, send it from a Server Component to the client, or hand it
 * to `/query` and `/next`. Args never carry a `signal`.
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

/** The result type of a `QuerySpec`. */
export type InferResult<S> =
  S extends QuerySpec<string, ReadMethod, infer R> ? R : never;

type NoSignal<A> = Omit<A, "signal">;

export interface TableSpecs<M extends AnyModels, T extends TableKey<M>, E> {
  findMany<const A extends NoSignal<FindManyArgs<M, T>> & FindExt<E, M, T>>(
    args?: A,
  ): QuerySpec<T, "findMany", Payload<M, T, A>[]>;
  findFirst<const A extends NoSignal<FindFirstArgs<M, T>> & FindExt<E, M, T>>(
    args?: A,
  ): QuerySpec<T, "findFirst", Payload<M, T, A> | null>;
  findUnique<
    const A extends NoSignal<ReadArgs<M, T>> & {
      readonly where: UniqueWhere<M, T>;
    } & FindExt<E, M, T>,
  >(
    args: A,
  ): QuerySpec<T, "findUnique", Payload<M, T, A> | null>;
  findById<const A extends NoSignal<ReadArgs<M, T>> & FindExt<E, M, T>>(
    id: PrimaryKeyValue<M, T>,
    args?: A,
  ): QuerySpec<T, "findById", Payload<M, T, A>>;
  count(
    args?: NoSignal<CountArgs<M, T>> & FindExt<E, M, T>,
  ): QuerySpec<T, "count", number>;
  aggregate<const A extends NoSignal<AggregateArgs<M, T>> & FindExt<E, M, T>>(
    args: A,
  ): QuerySpec<T, "aggregate", AggregateResult<M, T, A>>;
  exists(
    args?: { readonly where?: WhereInput<M, T> } & FindExt<E, M, T>,
  ): QuerySpec<T, "exists", boolean>;
  paginate<
    const A extends NoSignal<OffsetPageArgs<M, T> | CursorPageArgs<M, T>> &
      FindExt<E, M, T>,
  >(
    args: A,
  ): QuerySpec<T, "paginate", PageOf<M, T, A>>;
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

function trimUndefined(args: readonly unknown[]): unknown[] {
  const out = [...args];
  while (out.length > 0 && out.at(-1) === undefined) out.pop();
  return out;
}

export function isQuerySpec(value: unknown): value is QuerySpec {
  if (typeof value !== "object" || value === null) return false;
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

/** The argument object of a spec's method (`findById` takes it second). */
function specOptions(
  spec: QuerySpec,
): Readonly<Record<string, unknown>> | undefined {
  const value = spec.method === "findById" ? spec.args[1] : spec.args[0];
  // SAFETY: value is a non-null object, the shape of a read method's options argument.
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : undefined;
}

const builders = new WeakMap<SchemaMeta, IrBuilder>();

/**
 * App keys of every table a spec reads: its table, included relations and
 * relations used in `where`. Queries keyed by a spec go stale when any of
 * them changes. Invalid arguments yield just the spec's table; running the
 * spec reports the error.
 */
export function specTables(meta: SchemaMeta, spec: QuerySpec): string[] {
  try {
    return readTables(meta, spec);
  } catch {
    return [spec.table];
  }
}

function readTables(meta: SchemaMeta, spec: QuerySpec): string[] {
  let builder = builders.get(meta);
  if (!builder) {
    builder = new IrBuilder(meta);
    builders.set(meta, builder);
  }
  const table = tableMeta(meta, spec.table);
  const args = specOptions(spec);
  const counts =
    spec.method === "count" ||
    spec.method === "exists" ||
    spec.method === "aggregate";
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
