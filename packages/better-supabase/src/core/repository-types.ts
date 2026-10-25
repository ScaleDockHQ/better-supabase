import type {
  AggregateArgs,
  AggregateResult,
  CountArgs,
  GetArgs,
  ListArgs,
  Payload,
  ReadArgs,
  RequestArgs,
  WhereInput,
} from "../ir/args.ts";
import type { CountMode } from "../ir/types.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  PrimaryKeyValue,
  Row,
  TableKey,
  TableMeta,
  UniqueKeyName,
  UniqueWhere,
  Update,
} from "../schema/types.ts";
import type { StorageApi } from "../storage/storage-api.ts";
import type { BlockClientsOf, BlocksHelper, BucketsOf } from "./db-blocks.ts";
import type { BucketsHelper } from "./db-buckets.ts";
import type { Executor } from "./executor.ts";
import type { ApplyExtension, RequestContext } from "./plugin.ts";
import type { InferReadSetParams, ReadSet, ReadSetResult } from "./read-set.ts";
import type { AsyncResult } from "./result.ts";
import type { SearchArgs, SearchScore } from "./search.ts";
import type { InferResult, QuerySpec } from "./spec.ts";
import type { StandardSchemaV1 } from "./standard.ts";
import type { DbStats } from "./stats.ts";

export type FindExt<E, M extends AnyModels, T extends keyof M> = ApplyExtension<
  E,
  M,
  T,
  "findArgs"
>;

export type DeleteExt<
  E,
  M extends AnyModels,
  T extends keyof M,
> = ApplyExtension<E, M, T, "deleteArgs">;

export interface WriteArgs<
  M extends AnyModels,
  T extends keyof M,
> extends ReadArgs<M, T> {
  /** `false` skips `RETURNING` (needed when RLS hides the written row). */
  readonly returning?: boolean;
  /**
   * Keep caller-supplied values for columns that `updatedAtExtension()`,
   * `createdByExtension()` and `trashExtension()` fill (imports, backfills).
   * Without it they are refused.
   */
  readonly override?: boolean;
}

export interface UpdateArgs<
  M extends AnyModels,
  T extends keyof M,
> extends WriteArgs<M, T> {
  /**
   * More conditions the row must meet, such as a tenant or a status. A row with
   * this key that does not match returns `not_found`, in one request.
   */
  readonly where?: WhereInput<M, T>;
  /**
   * Optimistic concurrency: the update only applies when the row still matches.
   * Plain values mean equality; operators work as in `where`. A mismatch
   * returns a `stale` error, found with a second request.
   */
  readonly expect?: WhereInput<M, T>;
}

/**
 * The result of a many-row write by its `returning` option. Each case of
 * `returning` (`true`, `false`, absent) picks rows or `{ count }`, and a
 * widened `boolean` gives both. `Default` is what an absent option means:
 * `true` for `create` and `upsert` with an array, `false` for `update` and
 * `delete` with a filter.
 */
export type ManyOutcome<
  M extends AnyModels,
  T extends keyof M,
  A,
  Default extends boolean,
> =
  ReturningOption<A> extends infer R
    ? R extends true
      ? Payload<M, T, A>[]
      : R extends false
        ? { count: number }
        : Default extends true
          ? Payload<M, T, A>[]
          : { count: number }
    : never;

type ReturningOption<A> = "returning" extends keyof A
  ? A["returning" & keyof A]
  : undefined;

/**
 * `update({ where })` and `delete({ where })` return the rows with `returning:
 * true`.
 */
export type ManyResult<M extends AnyModels, T extends keyof M, A> = ManyOutcome<
  M,
  T,
  A,
  false
>;

/** A filter that picks several rows for `update` and `delete`. */
export interface RowFilter<M extends AnyModels, T extends keyof M> {
  readonly where: WhereInput<M, T>;
}

/** What `get()` takes: a primary key, a unique key or a filter. */
export type GetKey<M extends AnyModels, T extends keyof M> =
  | PrimaryKeyValue<M, T>
  | UniqueWhere<M, T>
  | RowFilter<M, T>;

/** Options of `update({ where })` and `delete({ where })`. */
export interface ManyWriteArgs<
  M extends AnyModels,
  T extends keyof M,
> extends RequestArgs {
  /** Return the written rows instead of `{ count }`. */
  readonly returning?: boolean;
  /** The columns to return with `returning: true`. */
  readonly select?: ReadArgs<M, T>["select"];
  /** Related rows to return with `returning: true`. */
  readonly include?: ReadArgs<M, T>["include"];
  /**
   * The most rows the call may change. When `where` matches more, the call
   * fails with `max_affected` and changes nothing. Over PostgREST it needs
   * PostgREST 13 or later (`Prefer: max-affected`).
   */
  readonly maxAffected?: number;
  /** How `{ count }` is counted over PostgREST. Defaults to `exact`. */
  readonly count?: CountMode;
  /**
   * Keep caller-supplied values for columns that `updatedAtExtension()`,
   * `createdByExtension()` and `trashExtension()` fill (imports, backfills).
   * Without it they are refused.
   */
  readonly override?: boolean;
}

/** Options of `create` and `upsert` with an array of rows. */
export interface WriteManyArgs<
  M extends AnyModels,
  T extends keyof M,
> extends WriteArgs<M, T> {
  /**
   * Columns some rows leave out become `null` instead of their column default.
   * Defaults to `false`, so a left-out column takes its default.
   */
  readonly defaultToNull?: boolean;
  /**
   * How `{ count }` is counted over PostgREST with `returning: false`. Defaults
   * to `exact`.
   */
  readonly count?: CountMode;
}

export type ConflictTarget<M extends AnyModels, T extends keyof M> =
  | "primaryKey"
  | UniqueKeyName<M, T>
  | readonly Extract<keyof Row<M, T>, string>[];

export interface UpsertArgs<
  M extends AnyModels,
  T extends keyof M,
> extends WriteArgs<M, T> {
  /** Unique constraint name or column list. Defaults to the primary key. */
  readonly onConflict?: ConflictTarget<M, T>;
  /** Keep the existing row instead of updating it (`ON CONFLICT DO NOTHING`). */
  readonly ignoreDuplicates?: boolean;
}

export type DeleteArgs = RequestArgs;

/** Options of `upsert` with an array of rows. */
export interface UpsertManyArgs<M extends AnyModels, T extends keyof M>
  extends UpsertArgs<M, T>, WriteManyArgs<M, T> {}

export type Returned<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly returning: false;
}
  ? null
  : Payload<M, T, A>;

export type OffsetPageArgs<M extends AnyModels, T extends keyof M> = Omit<
  ListArgs<M, T>,
  "limit" | "offset"
> & {
  /** 1-based page number. Defaults to 1. */
  readonly page?: number;
  readonly size: number;
  /** Also count all matching rows. */
  readonly count?: CountMode;
  /** Shorthand for `count: "exact"`. */
  readonly withCount?: boolean;
  readonly offset?: never;
  readonly limit?: never;
};

export type OffsetRangeArgs<M extends AnyModels, T extends keyof M> = Omit<
  ListArgs<M, T>,
  "limit" | "offset"
> & {
  /** Rows to skip before the page. */
  readonly offset: number;
  readonly limit: number;
  /** Also count all matching rows. */
  readonly count?: CountMode;
  /** Shorthand for `count: "exact"`. */
  readonly withCount?: boolean;
  readonly page?: never;
  readonly size?: never;
};

export type CursorPageArgs<M extends AnyModels, T extends keyof M> = Omit<
  ListArgs<M, T>,
  "limit" | "offset"
> & {
  /** Cursor from the previous page, or `null` for the first page. */
  readonly after: string | null;
  readonly size: number;
  /**
   * Also count every row matching `where` (ignoring the cursor) and return it
   * as `total`. The first page reads it from the page request; later pages cost
   * one more request.
   */
  readonly withCount?: boolean;
};

export interface OffsetPage<R, Counted extends boolean = false> {
  readonly items: R[];
  readonly page: {
    readonly number: number;
    readonly size: number;
    readonly total: Counted extends true ? number : number | null;
    readonly pages: Counted extends true ? number : number | null;
    readonly hasMore: boolean;
  };
}

export interface CursorPage<R> {
  readonly items: R[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

/** A cursor page that was asked for a count. */
export type CountedCursorPage<R> = CursorPage<R> & { readonly total: number };

type IsCounted<A> = A extends { readonly withCount: true }
  ? true
  : A extends { readonly count: "exact" | "planned" | "estimated" }
    ? true
    : false;

export type PageOf<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly after: unknown;
}
  ? IsCounted<A> extends true
    ? CountedCursorPage<Payload<M, T, A>>
    : CursorPage<Payload<M, T, A>>
  : IsCounted<A> extends true
    ? OffsetPage<Payload<M, T, A>, true>
    : OffsetPage<Payload<M, T, A>>;

export interface Repository<
  M extends AnyModels,
  T extends TableKey<M>,
  E = unknown,
> {
  readonly $tableName: T;
  readonly $meta: TableMeta;

  /** The rows matching `where`, ordered by `orderBy` or the primary key. */
  list<const A extends ListArgs<M, T> & FindExt<E, M, T>>(
    args?: A,
  ): AsyncResult<Payload<M, T, A>[]>;
  /**
   * One page of rows: by page number (`page`, `size`), by offset (`offset`,
   * `limit`) or by cursor (`after`, `size`).
   */
  page<
    const A extends (
      | OffsetPageArgs<M, T>
      | OffsetRangeArgs<M, T>
      | CursorPageArgs<M, T>
    ) &
      FindExt<E, M, T>,
  >(
    args: A,
  ): AsyncResult<PageOf<M, T, A>>;
  /**
   * The row with this primary key, these values for one unique key (`{ email
   * }`, `{ organizationId, slug }`), or the one row matching `{ where }`. No
   * row is a `not_found` error, or `null` with `optional: true`; several rows
   * matching `{ where }` are a `multiple_rows` error.
   */
  get<const A extends GetArgs<M, T> & FindExt<E, M, T>>(
    key: GetKey<M, T>,
    args?: A,
  ): AsyncResult<
    A extends { readonly optional: true }
      ? Payload<M, T, A> | null
      : Payload<M, T, A>
  >;
  count(args?: CountArgs<M, T> & FindExt<E, M, T>): AsyncResult<number>;
  /**
   * Counts, sums, averages, minimums and maximums in one request, grouped by
   * `groupBy` columns. Needs `pgrst.db_aggregates_enabled` over PostgREST.
   */
  aggregate<const A extends AggregateArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): AsyncResult<AggregateResult<M, T, A>>;

  /** Inserts one row, or several in one request when given an array. */
  /** Inserts one row, or several in one request when given an array. */
  create<const A extends WriteArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): AsyncResult<Returned<M, T, A>>;
  create<const A extends WriteManyArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): AsyncResult<ManyOutcome<M, T, A, true>>;
  /**
   * Updates the row with this key, or every row matching `{ where }`. A filter
   * that matches no rows by construction (empty, or every value `undefined`)
   * fails with `invalid_request` unless `allowAll` is `true`.
   */
  update(
    filter: RowFilter<M, T>,
    patch: Update<M, T>,
  ): AsyncResult<{ count: number }>;
  update<
    const A extends ManyWriteArgs<M, T> & {
      /** Update every visible row when `where` filters nothing. */
      readonly allowAll?: boolean;
    } & FindExt<E, M, T>,
  >(
    filter: RowFilter<M, T>,
    // NoInfer keeps the `const` inference from turning array and object values
    // into readonly types the column rejects.
    patch: NoInfer<Update<M, T>>,
    args: A,
  ): AsyncResult<ManyResult<M, T, A>>;
  update<const A extends UpdateArgs<M, T> = {}>(
    id: PrimaryKeyValue<M, T>,
    patch: Update<M, T>,
    args?: A,
  ): AsyncResult<Returned<M, T, A>>;
  /** Inserts or updates one row, or several when given an array. */
  upsert<const A extends UpsertArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): AsyncResult<
    A extends { readonly ignoreDuplicates: true }
      ? Returned<M, T, A> | null
      : Returned<M, T, A>
  >;
  upsert<const A extends UpsertManyArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): AsyncResult<ManyOutcome<M, T, A, true>>;
  /**
   * Deletes the row with this key (`not_found` when no visible row has it), or
   * every row matching `{ where }`, which must filter rows.
   */
  delete(filter: RowFilter<M, T>): AsyncResult<{ count: number }>;
  delete<
    const A extends ManyWriteArgs<M, T> & DeleteExt<E, M, T> & FindExt<E, M, T>,
  >(
    filter: RowFilter<M, T>,
    args: A,
  ): AsyncResult<ManyResult<M, T, A>>;
  delete(
    id: PrimaryKeyValue<M, T>,
    args?: DeleteArgs & DeleteExt<E, M, T>,
  ): AsyncResult<void>;

  /** Adds methods built on this repository. */
  extend<X extends object>(build: (base: this) => X): this & X;
}

export type RepositoryOf<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
> = Repository<M, T, E> & ApplyExtension<E, M, T, "methods">;

export interface RpcOptions<R> extends RequestArgs {
  /**
   * Validates the return value after decoding, so the schema sees the
   * configured casing and codecs; the result carries its output type.
   */
  readonly returns?: StandardSchemaV1<unknown, R>;
  readonly schema?: string;
  /**
   * Return what PostgREST sent, with database names and no codecs. Rows of a
   * table or a `returns table (...)` record are decoded like reads otherwise.
   */
  readonly raw?: boolean;
}

export type RpcArgs<F extends AnyFunctions, N extends keyof F> =
  Record<never, never> extends F[N]["Args"]
    ? [args?: F[N]["Args"]]
    : [args: F[N]["Args"]];

type IsUnion<T, U = T> = T extends unknown
  ? [U] extends [T]
    ? false
    : true
  : never;

/** Names generated as a union of `{ Args; Returns }`, one per overload. */
export type OverloadedName<F extends AnyFunctions> = {
  [K in keyof F]: true extends IsUnion<F[K]> ? K : never;
}[keyof F] &
  string;

export type PlainName<F extends AnyFunctions> = Exclude<
  Extract<keyof F, string>,
  OverloadedName<F>
>;

/** Overloaded names with an overload that a call without arguments matches. */
export type NoArgName<F extends AnyFunctions> = {
  [K in OverloadedName<F>]: Record<never, never> extends F[K]["Args"]
    ? K
    : never;
}[OverloadedName<F>];

/**
 * Property names without index signatures (`Record<PropertyKey, never>` has
 * none).
 */
type KnownKeys<T> = keyof {
  [
    K in keyof T as string extends K
      ? never
      : number extends K
        ? never
        : symbol extends K
          ? never
          : K
  ]: 0;
};

type RequiredKeys<T> = {
  [K in keyof T]-?: Record<never, never> extends Pick<T, K> ? never : K;
}[keyof T];

/**
 * The overloads PostgREST can pick for arguments `A`: every name in `A` is an
 * argument, and every argument without a default is in `A`. Overloads with the
 * same names stay a union, since the call can't tell them apart.
 */
type MatchingOverload<O, A> = A extends unknown
  ? O extends { readonly Args: infer OA }
    ? [Exclude<keyof A, KnownKeys<OA>>] extends [never]
      ? [Exclude<RequiredKeys<OA>, keyof A>] extends [never]
        ? O
        : never
      : never
    : never
  : never;

export type OverloadReturns<O, A> = [MatchingOverload<O, A>] extends [never]
  ? O extends { readonly Returns: infer R }
    ? R
    : never
  : MatchingOverload<O, A> extends { readonly Returns: infer R }
    ? R
    : never;

/**
 * `A` when its names pick an overload, with a name that no overload takes typed
 * `never`, and `never` when the names mix overloads.
 */
export type OverloadArgs<O extends { readonly Args: unknown }, A> = A &
  NoInfer<
    [MatchingOverload<O, A>] extends [never]
      ? never
      : {
          readonly [
            K in Exclude<
              keyof A,
              O extends { readonly Args: infer OA } ? KnownKeys<OA> : never
            >
          ]: never;
        }
  >;

export type RawRpcOptions = Omit<RpcOptions<unknown>, "returns" | "raw"> & {
  readonly raw: true;
};

export interface DbHelpers<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  B = unknown,
> {
  /** The underlying client (supabase-js), for anything the repository lacks. */
  readonly $client: C;
  /**
   * Storage as the same caller: `connect()`'s `storage` option, or the client's
   * `storage`. Pass it to `bucket.connect()` and the blocks, so Storage follows
   * whatever the `Db` runs as. Throws when the connection has neither, such as
   * a bare `Executor`.
   */
  readonly $storage: StorageApi;
  readonly $executor: Executor;
  readonly $context: RequestContext;
  /**
   * Calls a database function with typed arguments. Rows of a table or a
   * `returns table (...)` record come back in the configured casing, with
   * codecs applied; `raw: true` returns them as PostgREST sent them.
   */
  $rpc<N extends PlainName<F>>(
    name: N,
    ...rest: [...RpcArgs<F, N>, options: RawRpcOptions]
  ): AsyncResult<unknown>;
  $rpc<N extends PlainName<F>, R = F[N]["Returns"]>(
    name: N,
    ...rest: [...RpcArgs<F, N>, options?: RpcOptions<R>]
  ): AsyncResult<R>;
  /**
   * An overloaded function: the arguments match one overload, and the result is
   * the return type of the overloads with those argument names.
   */
  $rpc<N extends OverloadedName<F>, const A extends F[N]["Args"]>(
    name: N,
    args: OverloadArgs<F[N], A>,
    options: RawRpcOptions,
  ): AsyncResult<unknown>;
  $rpc<
    N extends OverloadedName<F>,
    const A extends F[N]["Args"],
    R = OverloadReturns<F[N], A>,
  >(
    name: N,
    args: OverloadArgs<F[N], A>,
    options?: RpcOptions<R>,
  ): AsyncResult<R>;
  $rpc<N extends NoArgName<F>>(
    name: N,
  ): AsyncResult<OverloadReturns<F[N], Record<never, never>>>;
  /** Same connection with more context (for example a tenant). */
  $with(context: RequestContext): Db<M, F, E, C, B>;
  /**
   * Same connection without plugins: no tenant scoping, soft-delete filters,
   * timestamps, rules or executor wrappers. For migrations and admin tools.
   * `keep` names plugins to leave installed, such as tracing (`keep:
   * ["otel"]`); a name that isn't installed throws a `TypeError`.
   */
  $withoutPlugins(options?: {
    readonly keep?: readonly string[];
  }): Db<M, F, unknown, C, B>;
  /**
   * The repository for a table named at runtime (MCP tools, admin screens).
   * Throws a `TypeError` for unknown names.
   */
  $table<T extends TableKey<M>>(name: T): RepositoryOf<M, T, E>;
  /** Calls, waves, tables and time for everything run through this `db`. */
  $stats(): DbStats;
  /** Runs a `QuerySpec` built with `betterSupabase.spec`. */
  $run<S extends QuerySpec<TableKey<M>>>(
    spec: S,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<InferResult<S>>;
  /**
   * Runs a read set as one round trip: a single GET to its function over
   * PostgREST, one transaction over SQL. Query plugins don't apply; RLS does.
   */
  $many<S extends ReadSet>(
    readSet: S,
    params: InferReadSetParams<S>,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<ReadSetResult<S>>;
  /**
   * Runs specs together: in parallel over PostgREST, in one transaction when
   * the executor has `batch`. Fails with the first error.
   */
  $many<const S extends readonly QuerySpec<TableKey<M>>[]>(
    specs: S,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<{ -readonly [K in keyof S]: InferResult<S[K]> }>;
  /**
   * The `k` rows nearest to `vector`, nearest first, through the
   * `search_<table>` function of the `vector-search` SQL module. RLS applies
   * inside the search; `where` filters the `k` rows it returns.
   */
  $search<T extends TableKey<M>, const A extends SearchArgs<M, T>>(
    table: T,
    args: A,
  ): AsyncResult<(Payload<M, T, A> & SearchScore<A>)[]>;
}

export type Db<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  B = unknown,
> = {
  readonly [T in TableKey<M>]: RepositoryOf<M, T, E>;
} & DbHelpers<M, F, E, C, B> &
  BucketsHelper<BucketsOf<B>> &
  BlocksHelper<BlockClientsOf<B>, TableKey<M>>;
