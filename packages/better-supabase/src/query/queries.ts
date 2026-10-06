import type {
  DataTag,
  InfiniteData,
  QueryClient,
  SkipToken,
} from "@tanstack/query-core";

import type { CacheAdapter } from "../core/cache.ts";
import type { BetterSupabase } from "../core/define.ts";
import type {
  CursorPage,
  CursorPageArgs,
  Db,
  DeleteArgs,
  DeleteExt,
  FindExt,
  OffsetPage,
  OffsetPageArgs,
  OffsetRangeArgs,
  Returned,
  UpdateArgs,
  UpsertArgs,
  WriteArgs,
} from "../core/repository-types.ts";
import type { AsyncResult } from "../core/result.ts";
import type { InferResult, QuerySpec } from "../core/spec.ts";
import type {
  AggregateArgs,
  AggregateResult,
  CountArgs,
  FindFirstArgs,
  FindOnlyArgs,
  FindManyArgs,
  Payload,
  ReadArgs,
  WhereInput,
} from "../ir/args.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  PrimaryKeyValue,
  TableKey,
  UniqueWhere,
  Update,
} from "../schema/types.ts";

import { type DbError, DbException } from "../core/errors.ts";
import { invalidationTargets } from "../ir/tables.ts";
import { type BetterQueryMeta, invalidateTables } from "./invalidate.ts";

/** Query errors stay `DbException`s, even for an `betterSupabase` with `mapError()`. */
const asException = (error: DbError) => new DbException(error);

export { invalidateTables };
export type { BetterQueryMeta };

export type QueryKeyOf<T> = DataTag<readonly unknown[], T, DbException>;

type QueryFnOf<T> =
  | ((context: { readonly signal: AbortSignal }) => Promise<T>)
  | SkipToken;

/** Options for `useQuery`, `createQuery`, `injectQuery`, `queryClient.fetchQuery` and `prefetchQuery`. */
export interface QueryOptionsOf<T> {
  readonly queryKey: QueryKeyOf<T>;
  readonly queryFn: QueryFnOf<T>;
  readonly meta: BetterQueryMeta;
  readonly staleTime?: number;
}

/** Options for infinite queries over cursor (`string | null`) or offset (`number`) pages. */
export interface InfiniteOptionsOf<P, Param> {
  readonly queryKey: DataTag<readonly unknown[], InfiniteData<P>, DbException>;
  readonly queryFn: (context: {
    readonly signal: AbortSignal;
    readonly pageParam: Param;
  }) => Promise<P>;
  readonly initialPageParam: Param;
  readonly getNextPageParam: (last: P) => Param | undefined;
  readonly meta: BetterQueryMeta;
  readonly staleTime?: number;
}

/** Options for `useMutation`. Invalidates every query that read a changed table. */
export interface MutationOptionsOf<V, R> {
  readonly mutationKey: readonly unknown[];
  readonly mutationFn: (variables: V) => Promise<R>;
  readonly onSuccess: (
    data: R,
    variables: V,
    onMutateResult: unknown,
    context: { readonly client: QueryClient },
  ) => Promise<void>;
}

export interface TableQueries<M extends AnyModels, T extends TableKey<M>, E> {
  /** Prefix of every key for this table's own queries. */
  readonly key: readonly ["bs", T];
  findMany<const A extends FindManyArgs<M, T> & FindExt<E, M, T>>(
    args?: A | SkipToken,
  ): QueryOptionsOf<Payload<M, T, A>[]>;
  findFirst<const A extends FindFirstArgs<M, T> & FindExt<E, M, T>>(
    args?: A | SkipToken,
  ): QueryOptionsOf<Payload<M, T, A> | null>;
  findOnly<const A extends FindOnlyArgs<M, T> & FindExt<E, M, T>>(
    args: A | SkipToken,
  ): QueryOptionsOf<Payload<M, T, A> | null>;
  findUnique<
    const A extends ReadArgs<M, T> & {
      readonly where: UniqueWhere<M, T>;
    } & FindExt<E, M, T>,
  >(
    args: A | SkipToken,
  ): QueryOptionsOf<Payload<M, T, A> | null>;
  findById<const A extends ReadArgs<M, T> & FindExt<E, M, T>>(
    id: PrimaryKeyValue<M, T> | SkipToken,
    args?: A,
  ): QueryOptionsOf<Payload<M, T, A>>;
  count(
    args?: (CountArgs<M, T> & FindExt<E, M, T>) | SkipToken,
  ): QueryOptionsOf<number>;
  aggregate<const A extends AggregateArgs<M, T> & FindExt<E, M, T>>(
    args: A | SkipToken,
  ): QueryOptionsOf<AggregateResult<M, T, A>>;
  exists(
    args?:
      | ({ readonly where?: WhereInput<M, T> } & FindExt<E, M, T>)
      | SkipToken,
  ): QueryOptionsOf<boolean>;
  paginate<
    const A extends (OffsetPageArgs<M, T> | OffsetRangeArgs<M, T>) &
      FindExt<E, M, T>,
  >(
    args: A | SkipToken,
  ): QueryOptionsOf<OffsetPage<Payload<M, T, A>>>;
  /** Cursor pages for `useInfiniteQuery`. */
  infinite<
    const A extends Omit<CursorPageArgs<M, T>, "after"> & FindExt<E, M, T>,
  >(
    args: A,
  ): InfiniteOptionsOf<CursorPage<Payload<M, T, A>>, string | null>;
  /** Numbered pages for `useInfiniteQuery`, starting at `args.page` (default 1). */
  infinitePages<const A extends OffsetPageArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): InfiniteOptionsOf<OffsetPage<Payload<M, T, A>>, number>;
  create<const A extends WriteArgs<M, T> = {}>(
    args?: A,
  ): MutationOptionsOf<Insert<M, T>, Returned<M, T, A>>;
  update<const A extends UpdateArgs<M, T> = {}>(
    args?: A,
  ): MutationOptionsOf<
    { readonly id: PrimaryKeyValue<M, T>; readonly patch: Update<M, T> },
    Returned<M, T, A>
  >;
  upsert<const A extends UpsertArgs<M, T> = {}>(
    args?: A,
  ): MutationOptionsOf<Insert<M, T>, Returned<M, T, A>>;
  delete(
    args?: DeleteArgs & DeleteExt<E, M, T>,
  ): MutationOptionsOf<PrimaryKeyValue<M, T>, void>;
}

type RpcArgsOf<F extends AnyFunctions, N extends keyof F> = F[N]["Args"];

export interface QueryHelpers<M extends AnyModels, F extends AnyFunctions> {
  /** Prefix of every better-supabase key. */
  readonly $key: readonly ["bs"];
  /** Query options for a `QuerySpec`, for example one sent from a Server Component. */
  $spec<S extends QuerySpec<TableKey<M>>>(
    spec: S | SkipToken,
  ): QueryOptionsOf<InferResult<S>>;
  /** Fetches a spec into `queryClient` for server rendering and hydration. */
  $prefetch(
    queryClient: QueryClient,
    spec: QuerySpec<TableKey<M>>,
  ): Promise<void>;
  /** Query options for a database function. `tables` lists what it reads, for invalidation. */
  $rpc<N extends Extract<keyof F, string>>(
    name: N,
    args?: RpcArgsOf<F, N> | SkipToken,
    options?: { readonly tables?: readonly TableKey<M>[] },
  ): QueryOptionsOf<F[N]["Returns"]>;
  /** Mutation options for a database function; invalidates what `betterSupabase.defineRpc` declared. */
  $rpcMutation<N extends Extract<keyof F, string>>(
    name: N,
  ): MutationOptionsOf<RpcArgsOf<F, N>, F[N]["Returns"]>;
}

export type BetterQueries<
  M extends AnyModels,
  E,
  F extends AnyFunctions = AnyFunctions,
> = {
  readonly [T in TableKey<M>]: TableQueries<M, T, E>;
} & QueryHelpers<M, F>;

export interface QueriesOptions {
  /**
   * `staleTime` for every query option. Set it above zero when rendering on
   * the server so hydrated data isn't refetched on mount.
   */
  readonly staleTime?: number;
}

type AnyRepository = Record<
  string,
  (...args: unknown[]) => AsyncResult<unknown>
>;

interface AnyDb {
  readonly [table: string]: unknown;
  $run(
    spec: QuerySpec,
    options?: { signal?: AbortSignal },
  ): AsyncResult<unknown>;
  $rpc(
    name: string,
    args?: unknown,
    options?: { signal?: AbortSignal },
  ): AsyncResult<unknown>;
}

function isSkip(value: unknown): value is SkipToken {
  return typeof value === "symbol";
}

function withoutSignal(value: unknown): unknown {
  if (typeof value !== "object" || value === null) return value;
  // SAFETY: value is a non-null object here, and only the signal key is removed.
  const { signal: _signal, ...rest } = value as Record<string, unknown>;
  return rest;
}

interface Runtime {
  readonly betterSupabase: BetterSupabase;
  readonly db: () => AnyDb;
  readonly staleTime: number | undefined;
}

function specQuery(
  runtime: Runtime,
  spec: QuerySpec | SkipToken,
  key?: readonly unknown[],
) {
  const stale =
    runtime.staleTime === undefined ? {} : { staleTime: runtime.staleTime };
  if (isSkip(spec)) {
    return {
      queryKey: key ?? ["bs", "$skip"],
      queryFn: spec,
      meta: { bsTables: [] },
      ...stale,
    };
  }
  return {
    queryKey: key ?? ["bs", spec.table, spec.method, ...spec.args],
    queryFn: ({ signal }: { signal: AbortSignal }) =>
      runtime.db().$run(spec, { signal }).orThrow(asException),
    meta: { bsTables: runtime.betterSupabase.tablesOf(spec) },
    ...stale,
  };
}

type SpecTables = Record<
  string,
  Record<string, (...args: unknown[]) => QuerySpec>
>;

function tableQueries(
  runtime: Runtime,
  table: string,
): Record<string, unknown> {
  const key = ["bs", table] as const;
  // SAFETY: spec is generic over the schema; entries are looked up by table name.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- `spec` is generic over the schema; entries are looked up by table name.
  const tables = runtime.betterSupabase.spec as unknown as SpecTables;
  const specs = tables[table]!;
  const stale =
    runtime.staleTime === undefined ? {} : { staleTime: runtime.staleTime };
  const read =
    (method: string) =>
    (args?: unknown): unknown =>
      isSkip(args)
        ? specQuery(runtime, args, [...key, method, "$skip"])
        : specQuery(runtime, specs[method]!(withoutSignal(args)));
  const repo = (): AnyRepository => {
    // SAFETY: the db is indexed by table name, and a missing repository is checked below.
    const found = runtime.db()[table] as AnyRepository | undefined;
    if (!found)
      throw new TypeError(`better-supabase: unknown table "${table}"`);
    return found;
  };
  const call = (method: string, ...args: unknown[]): AsyncResult<unknown> => {
    const fn = repo()[method];
    if (!fn)
      throw new TypeError(
        `better-supabase: ${table}.${method} is not available`,
      );
    return fn(...args);
  };
  const mutation = (
    op: string,
    run: (variables: never) => AsyncResult<unknown>,
    tables: readonly string[],
  ) => ({
    mutationKey: [...key, op],
    mutationFn: (variables: never) => run(variables).orThrow(asException),
    onSuccess: (
      _data: unknown,
      _variables: unknown,
      _result: unknown,
      context: { client: QueryClient },
    ) => invalidateTables(context.client, tables),
  });

  return {
    key,
    findMany: read("findMany"),
    findFirst: read("findFirst"),
    findOnly: read("findOnly"),
    findUnique: read("findUnique"),
    count: read("count"),
    aggregate: read("aggregate"),
    exists: read("exists"),
    paginate: read("paginate"),
    findById: (id: unknown, args?: object) =>
      isSkip(id)
        ? specQuery(runtime, id, [...key, "findById", "$skip"])
        : specQuery(runtime, specs["findById"]!(id, withoutSignal(args))),
    infinite: (args: object) => {
      // SAFETY: withoutSignal returns a copy of the object it received.
      const base = withoutSignal(args) as object;
      return {
        queryKey: [...key, "infinite", base],
        queryFn: ({
          signal,
          pageParam,
        }: {
          signal: AbortSignal;
          pageParam: string | null;
        }) =>
          runtime
            .db()
            .$run(specs["paginate"]!({ ...base, after: pageParam }), { signal })
            .orThrow(asException),
        initialPageParam: null,
        getNextPageParam: (last: { nextCursor: string | null }) =>
          last.nextCursor ?? undefined,
        meta: {
          bsTables: runtime.betterSupabase.tablesOf(
            specs["paginate"]!({ ...base, after: null }),
          ),
        },
        ...stale,
      };
    },
    infinitePages: (args: { page?: number }) => {
      // SAFETY: withoutSignal returns a copy of the object it received.
      const base = withoutSignal(args) as { page?: number };
      return {
        queryKey: [...key, "infinitePages", base],
        queryFn: ({
          signal,
          pageParam,
        }: {
          signal: AbortSignal;
          pageParam: number;
        }) =>
          runtime
            .db()
            .$run(specs["paginate"]!({ ...base, page: pageParam }), { signal })
            .orThrow(asException),
        initialPageParam: base.page ?? 1,
        getNextPageParam: (last: OffsetPage<unknown>) =>
          last.page.hasMore ? last.page.number + 1 : undefined,
        meta: {
          bsTables: runtime.betterSupabase.tablesOf(specs["paginate"]!(base)),
        },
        ...stale,
      };
    },
    create: (args?: object) =>
      mutation("create", (data) => call("create", data, args), [table]),
    update: (args?: object) =>
      mutation(
        "update",
        (variables: { id: unknown; patch: unknown }) =>
          call("update", variables.id, variables.patch, args),
        [table],
      ),
    upsert: (args?: object) =>
      mutation("upsert", (data) => call("upsert", data, args), [table]),
    delete: (args?: object) =>
      mutation(
        "delete",
        (id) => call("delete", id, args),
        invalidationTargets(runtime.betterSupabase.meta, table),
      ),
  };
}

/**
 * TanStack Query option factories for every table, framework-neutral: pass
 * them to `useQuery` (React), `createQuery` (Svelte, Solid), `useQuery`
 * (Vue) or `injectQuery` (Angular). Payload types flow into the cache, errors
 * are `DbException`s, and mutations invalidate every query that read a
 * changed table.
 *
 * ```ts
 * const q = createQueries(betterSupabase, () => bs.db);
 * const { data } = useQuery(q.customers.findMany({ select: ['id', 'name'] }));
 * ```
 */
export function createQueries<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  db: Db<M, F, E, unknown> | (() => Db<M, F, E, unknown>),
  options: QueriesOptions = {},
): BetterQueries<M, E, F> {
  // SAFETY: the runtime erases schema generics and BetterQueries<M, E, F> restores them.
  const runtime: Runtime = {
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the runtime erases schema generics and `BetterQueries<M, E, F>` restores them.
    betterSupabase: betterSupabase as unknown as Runtime["betterSupabase"],
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the runtime erases schema generics and `BetterQueries<M, E, F>` restores them.
    db: (typeof db === "function" ? db : () => db) as unknown as () => AnyDb,
    staleTime: options.staleTime,
  };
  const stale =
    options.staleTime === undefined ? {} : { staleTime: options.staleTime };
  // SAFETY: specQuery returns query options that prefetchQuery accepts; the
  // generics differ only by the erased schema.
  const queries: Record<string, unknown> = {
    $key: ["bs"],
    $spec: (spec: QuerySpec | SkipToken) => specQuery(runtime, spec),
    $prefetch: (client: QueryClient, spec: QuerySpec) =>
      // oxlint-disable-next-line typescript/no-deprecated -- `query()` needs @tanstack/query-core 5.104; the peer range is ^5.
      client.prefetchQuery(specQuery(runtime, spec) as never),
    $rpc: (
      name: string,
      args?: unknown,
      rpcOptions: { tables?: readonly string[] } = {},
    ) => ({
      queryKey: ["bs", "$rpc", name, isSkip(args) ? "$skip" : (args ?? {})],
      queryFn: isSkip(args)
        ? args
        : ({ signal }: { signal: AbortSignal }) =>
            runtime
              .db()
              .$rpc(name, args ?? {}, { signal })
              .orThrow(asException),
      meta: { bsTables: rpcOptions.tables ?? [] },
      ...stale,
    }),
    $rpcMutation: (name: string) => ({
      mutationKey: ["bs", "$rpc", name],
      mutationFn: (args: unknown) =>
        runtime
          .db()
          .$rpc(name, args ?? {})
          .orThrow(asException),
      onSuccess: (
        _data: unknown,
        _variables: unknown,
        _result: unknown,
        context: { client: QueryClient },
      ) =>
        invalidateTables(
          context.client,
          (betterSupabase.options.rpc?.[name]?.invalidates ?? []).flatMap(
            (table) => invalidationTargets(betterSupabase.meta, table),
          ),
        ),
    }),
  };
  for (const table of Object.keys(betterSupabase.meta.tables)) {
    let built: Record<string, unknown> | undefined;
    Object.defineProperty(queries, table, {
      enumerable: true,
      get: () => {
        built ??= tableQueries(runtime, table);
        return built;
      },
    });
  }
  // SAFETY: queries has one entry per table and procedure, which is the shape
  // of BetterQueries<M, E, F>.
  return queries as BetterQueries<M, E, F>;
}

/** Invalidates every query that read a table in the target. */
export function queryCache(client: QueryClient): CacheAdapter {
  return {
    name: "tanstack-query",
    invalidate: (target) => invalidateTables(client, target.tables),
  };
}

/** Invalidates affected queries for every mutation and declared RPC `betterSupabase` performs in this runtime. */
export function invalidateOnMutation<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(betterSupabase: BetterSupabase<M, D, F, E>, client: QueryClient): () => void {
  return betterSupabase.cache(queryCache(client));
}
