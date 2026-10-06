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
import type { Executor } from "./executor.ts";
import type { ApplyExtension, RequestContext } from "./plugin.ts";
import type { InferReadSetParams, ReadSet, ReadSetResult } from "./read-set.ts";
import type { AsyncResult } from "./result.ts";
import type { SearchArgs } from "./search.ts";
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
   * Keep caller-supplied values for columns that `timestamps()`, `actor()`
   * and `softDelete()` fill (imports, backfills). Without it they are refused.
   */
  readonly override?: boolean;
}

export interface UpdateArgs<
  M extends AnyModels,
  T extends keyof M,
> extends WriteArgs<M, T> {
  /**
   * More conditions the row must meet, such as a tenant or a status. A row
   * with this key that does not match returns `not_found`, in one request.
   */
  readonly where?: WhereInput<M, T>;
  /**
   * Optimistic concurrency: the update only applies when the row still
   * matches. Plain values mean equality; operators work as in `where`. A
   * mismatch returns a `stale` error, found with a second request.
   */
  readonly expect?: WhereInput<M, T>;
}

/** `updateMany` and `deleteMany` return the written rows with `returning: true`. */
export type ManyResult<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly returning: true;
}
  ? Payload<M, T, A>[]
  : { count: number };

export interface ManyReturningArgs<M extends AnyModels, T extends keyof M> {
  readonly where: WhereInput<M, T>;
  /** Return the written rows instead of `{ count }`. */
  readonly returning?: boolean;
  /** The columns to return with `returning: true`. */
  readonly select?: ReadArgs<M, T>["select"];
  /** Related rows to return with `returning: true`. */
  readonly include?: ReadArgs<M, T>["include"];
  readonly signal?: AbortSignal;
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

export interface DeleteArgs {
  readonly signal?: AbortSignal;
}

export type Returned<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly returning: false;
}
  ? null
  : Payload<M, T, A>;

export type OffsetPageArgs<M extends AnyModels, T extends keyof M> = Omit<
  FindManyArgs<M, T>,
  "limit" | "offset"
> & {
  /** 1-based page number. Defaults to 1. */
  readonly page?: number;
  readonly size: number;
  /** Also count all matching rows. */
  readonly count?: CountMode;
  readonly offset?: never;
  readonly limit?: never;
};

export type OffsetRangeArgs<M extends AnyModels, T extends keyof M> = Omit<
  FindManyArgs<M, T>,
  "limit" | "offset"
> & {
  /** Rows to skip before the page. */
  readonly offset: number;
  readonly limit: number;
  /** Also count all matching rows. */
  readonly count?: CountMode;
  readonly page?: never;
  readonly size?: never;
};

export type CursorPageArgs<M extends AnyModels, T extends keyof M> = Omit<
  FindManyArgs<M, T>,
  "limit" | "offset"
> & {
  /** Cursor from the previous page, or `null` for the first page. */
  readonly after: string | null;
  readonly size: number;
};

export interface OffsetPage<R> {
  readonly items: R[];
  readonly page: {
    readonly number: number;
    readonly size: number;
    readonly total: number | null;
    readonly pages: number | null;
    readonly hasMore: boolean;
  };
}

export interface CursorPage<R> {
  readonly items: R[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

export type PageOf<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly after: unknown;
}
  ? CursorPage<Payload<M, T, A>>
  : OffsetPage<Payload<M, T, A>>;

export interface Repository<
  M extends AnyModels,
  T extends TableKey<M>,
  E = unknown,
> {
  readonly $tableName: T;
  readonly $meta: TableMeta;

  findMany<const A extends FindManyArgs<M, T> & FindExt<E, M, T>>(
    args?: A,
  ): AsyncResult<Payload<M, T, A>[]>;
  findFirst<const A extends FindFirstArgs<M, T> & FindExt<E, M, T>>(
    args?: A,
  ): AsyncResult<Payload<M, T, A> | null>;
  /**
   * The one row matching `where`, or `null` when none does, like supabase-js
   * `maybeSingle()`. Several matching rows are a `multiple_rows` error, so
   * a filter that should pick one row never reads an arbitrary one.
   */
  findOnly<const A extends FindOnlyArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): AsyncResult<Payload<M, T, A> | null>;
  /**
   * The row with these values for the primary key or one named unique key
   * (`{ email }`, `{ organizationId, slug }`), or `null`.
   */
  findUnique<
    const A extends ReadArgs<M, T> & {
      readonly where: UniqueWhere<M, T>;
    } & FindExt<E, M, T>,
  >(
    args: A,
  ): AsyncResult<Payload<M, T, A> | null>;
  /** Returns a `not_found` error when no visible row has this key. */
  findById<const A extends ReadArgs<M, T> & FindExt<E, M, T>>(
    id: PrimaryKeyValue<M, T>,
    args?: A,
  ): AsyncResult<Payload<M, T, A>>;
  count(args?: CountArgs<M, T> & FindExt<E, M, T>): AsyncResult<number>;
  /**
   * Counts, sums, averages, minimums and maximums in one request, grouped by
   * `groupBy` columns. Needs `pgrst.db_aggregates_enabled` over PostgREST.
   */
  aggregate<const A extends AggregateArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): AsyncResult<AggregateResult<M, T, A>>;
  exists(
    args?: {
      readonly where?: WhereInput<M, T>;
      readonly signal?: AbortSignal;
    } & FindExt<E, M, T>,
  ): AsyncResult<boolean>;
  paginate<
    const A extends (
      | OffsetPageArgs<M, T>
      | OffsetRangeArgs<M, T>
      | CursorPageArgs<M, T>
    ) &
      FindExt<E, M, T>,
  >(
    args: A,
  ): AsyncResult<PageOf<M, T, A>>;

  create<const A extends WriteArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): AsyncResult<Returned<M, T, A>>;
  createMany<const A extends WriteArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): AsyncResult<
    A extends { readonly returning: false }
      ? { count: number }
      : Payload<M, T, A>[]
  >;
  update<const A extends UpdateArgs<M, T> = {}>(
    id: PrimaryKeyValue<M, T>,
    patch: Update<M, T>,
    args?: A,
  ): AsyncResult<Returned<M, T, A>>;
  updateMany<
    const A extends ManyReturningArgs<M, T> & {
      readonly data: Update<M, T>;
    } & FindExt<E, M, T>,
  >(
    args: A,
  ): AsyncResult<ManyResult<M, T, A>>;
  upsert<const A extends UpsertArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): AsyncResult<
    A extends { readonly ignoreDuplicates: true }
      ? Returned<M, T, A> | null
      : Returned<M, T, A>
  >;
  upsertMany<const A extends UpsertArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): AsyncResult<
    A extends { readonly returning: false }
      ? { count: number }
      : Payload<M, T, A>[]
  >;
  /** Returns a `not_found` error when no visible row has this key. */
  delete(
    id: PrimaryKeyValue<M, T>,
    args?: DeleteArgs & DeleteExt<E, M, T>,
  ): AsyncResult<void>;
  deleteMany<
    const A extends ManyReturningArgs<M, T> &
      DeleteExt<E, M, T> &
      FindExt<E, M, T>,
  >(
    args: A,
  ): AsyncResult<ManyResult<M, T, A>>;

  /** Adds methods built on this repository. */
  extend<X extends object>(build: (base: this) => X): this & X;
}

export type RepositoryOf<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
> = Repository<M, T, E> & ApplyExtension<E, M, T, "methods">;

export interface RpcOptions<R> {
  readonly signal?: AbortSignal;
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

type RpcArgs<F extends AnyFunctions, N extends keyof F> =
  Record<never, never> extends F[N]["Args"]
    ? [args?: F[N]["Args"]]
    : [args: F[N]["Args"]];

export interface DbHelpers<M extends AnyModels, F extends AnyFunctions, E, C> {
  /** The underlying client (supabase-js), for anything the repository lacks. */
  readonly $client: C;
  readonly $executor: Executor;
  readonly $context: RequestContext;
  /**
   * Calls a database function with typed arguments. Rows of a table or a
   * `returns table (...)` record come back in the configured casing, with
   * codecs applied; `raw: true` returns them as PostgREST sent them.
   */
  $rpc<N extends Extract<keyof F, string>>(
    name: N,
    ...rest: [
      ...RpcArgs<F, N>,
      options: Omit<RpcOptions<unknown>, "returns" | "raw"> & {
        readonly raw: true;
      },
    ]
  ): AsyncResult<unknown>;
  $rpc<N extends Extract<keyof F, string>, R = F[N]["Returns"]>(
    name: N,
    ...rest: [...RpcArgs<F, N>, options?: RpcOptions<R>]
  ): AsyncResult<R>;
  /** Same connection with more context (for example a tenant). */
  $with(context: RequestContext): Db<M, F, E, C>;
  /**
   * Same connection without plugins: no tenant scoping, soft-delete filters,
   * timestamps, rules or executor wrappers. For migrations and admin tools.
   * `keep` names plugins to leave installed, such as tracing (`keep: ["otel"]`);
   * a name that isn't installed throws a `TypeError`.
   */
  $withoutPlugins(options?: {
    readonly keep?: readonly string[];
  }): Db<M, F, unknown, C>;
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
   * `search_<table>` function of the `vector-search` SQL module. RLS
   * applies inside the search; `where` filters the `k` rows it returns.
   */
  $search<T extends TableKey<M>, const A extends SearchArgs<M, T>>(
    table: T,
    args: A,
  ): AsyncResult<Payload<M, T, A>[]>;
}

export type Db<M extends AnyModels, F extends AnyFunctions, E, C> = {
  readonly [T in TableKey<M>]: RepositoryOf<M, T, E>;
} & DbHelpers<M, F, E, C>;
