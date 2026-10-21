import type { Result as BetterResult } from "better-result";

import type { DbError } from "../core/errors.ts";
import type { ApplyExtension } from "../core/plugin.ts";
import type {
  InferReadSetParams,
  ReadSet,
  ReadSetResult,
} from "../core/read-set.ts";
import type {
  CursorPageArgs,
  Db,
  DeleteArgs,
  DeleteExt,
  FindExt,
  ManyResult,
  ManyReturningArgs,
  NoArgName,
  OffsetPageArgs,
  OffsetRangeArgs,
  OverloadArgs,
  OverloadedName,
  OverloadReturns,
  PageOf,
  PlainName,
  RawRpcOptions,
  Returned,
  RpcArgs,
  RpcOptions,
  UpdateArgs,
  UpsertArgs,
  UpsertManyArgs,
  WriteArgs,
  WriteManyArgs,
} from "../core/repository-types.ts";
import type { BetterResultApi } from "../core/result.ts";
import type { SearchArgs, SearchScore } from "../core/search.ts";
import type { InferResult, QuerySpec } from "../core/spec.ts";
import type {
  AggregateArgs,
  AggregateResult,
  CountArgs,
  FindFirstArgs,
  FindManyArgs,
  FindOnlyArgs,
  Payload,
  ReadArgs,
  RequestArgs,
  WhereInput,
} from "../ir/args.ts";
import type {
  ListDefinition,
  ListExtra,
  ListPage,
  ListPagination,
  ListQuery,
} from "../list/list-query.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  PrimaryKeyValue,
  TableKey,
  TableMeta,
  UniqueWhere,
  Update,
} from "../schema/types.ts";

import { AsyncResult, toBetterResult } from "../core/result.ts";

/**
 * Better-result's `Result` namespace with the function each `DbError` goes
 * through.
 */
export interface BetterResultMapping<E> {
  readonly Result: BetterResultApi<unknown, unknown>;
  readonly mapError: (error: DbError) => E;
}

/** What `withBetterResult` calls on a `defineBetterResultErrors` converter. */
export interface BetterResultErrorsLike {
  (result: AsyncResult<unknown>): unknown;
  map(error: DbError): unknown;
}

/** A `defineBetterResultErrors` converter or a `{ Result, mapError }` mapping. */
export type BetterResultConverter =
  | BetterResultErrorsLike
  | BetterResultMapping<unknown>;

/** The error type a converter produces. */
export type ConvertedError<X> =
  X extends BetterResultMapping<infer E>
    ? E
    : X extends { map(error: DbError): infer E }
      ? E
      : never;

type Out<T, Err> = Promise<BetterResult<T, Err>>;

/**
 * A repository whose reads and writes return better-result values. Its
 * signatures mirror `Repository`, so `select` and `include` still type the
 * rows.
 */
export interface BetterResultRepository<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
  Err,
> {
  readonly $tableName: T;
  readonly $meta: TableMeta;

  findMany<const A extends FindManyArgs<M, T> & FindExt<E, M, T>>(
    args?: A,
  ): Out<Payload<M, T, A>[], Err>;
  findFirst<const A extends FindFirstArgs<M, T> & FindExt<E, M, T>>(
    args?: A,
  ): Out<Payload<M, T, A> | null, Err>;
  findOnly<const A extends FindOnlyArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): Out<Payload<M, T, A> | null, Err>;
  findUnique<
    const A extends ReadArgs<M, T> & {
      readonly where: UniqueWhere<M, T>;
    } & FindExt<E, M, T>,
  >(
    args: A,
  ): Out<Payload<M, T, A> | null, Err>;
  findById<const A extends ReadArgs<M, T> & FindExt<E, M, T>>(
    id: PrimaryKeyValue<M, T>,
    args?: A,
  ): Out<Payload<M, T, A>, Err>;
  count(args?: CountArgs<M, T> & FindExt<E, M, T>): Out<number, Err>;
  aggregate<const A extends AggregateArgs<M, T> & FindExt<E, M, T>>(
    args: A,
  ): Out<AggregateResult<M, T, A>, Err>;
  exists(
    args?: RequestArgs & { readonly where?: WhereInput<M, T> } & FindExt<
        E,
        M,
        T
      >,
  ): Out<boolean, Err>;
  paginate<
    const A extends (
      | OffsetPageArgs<M, T>
      | OffsetRangeArgs<M, T>
      | CursorPageArgs<M, T>
    ) &
      FindExt<E, M, T>,
  >(
    args: A,
  ): Out<PageOf<M, T, A>, Err>;

  create<const A extends WriteArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): Out<Returned<M, T, A>, Err>;
  createMany<const A extends WriteManyArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): Out<
    A extends { readonly returning: false }
      ? { count: number }
      : Payload<M, T, A>[],
    Err
  >;
  update<const A extends UpdateArgs<M, T> = {}>(
    id: PrimaryKeyValue<M, T>,
    patch: Update<M, T>,
    args?: A,
  ): Out<Returned<M, T, A>, Err>;
  updateMany<
    const A extends ManyReturningArgs<M, T> & {
      readonly data: Update<M, T>;
      readonly allowAll?: boolean;
    } & FindExt<E, M, T>,
  >(
    args: A,
  ): Out<ManyResult<M, T, A>, Err>;
  upsert<const A extends UpsertArgs<M, T> = {}>(
    data: Insert<M, T>,
    args?: A,
  ): Out<
    A extends { readonly ignoreDuplicates: true }
      ? Returned<M, T, A> | null
      : Returned<M, T, A>,
    Err
  >;
  upsertMany<const A extends UpsertManyArgs<M, T> = {}>(
    rows: readonly Insert<M, T>[],
    args?: A,
  ): Out<
    A extends { readonly returning: false }
      ? { count: number }
      : Payload<M, T, A>[],
    Err
  >;
  delete(
    id: PrimaryKeyValue<M, T>,
    args?: DeleteArgs & DeleteExt<E, M, T>,
  ): Out<void, Err>;
  deleteMany<
    const A extends ManyReturningArgs<M, T> &
      DeleteExt<E, M, T> &
      FindExt<E, M, T>,
  >(
    args: A,
  ): Out<ManyResult<M, T, A>, Err>;
}

/**
 * Plugin methods that return an `AsyncResult` return a better-result value. A
 * generic plugin method keeps its parameters but loses its type parameters;
 * call it on `$db` and pass the result to `$from` instead.
 */
export type BetterResultMethods<X, Err> = {
  readonly [K in keyof X]: X[K] extends (
    ...args: infer P
  ) => AsyncResult<infer R>
    ? (...args: P) => Out<R, Err>
    : X[K];
};

export type BetterResultRepositoryOf<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
  Err,
> = BetterResultRepository<M, T, E, Err> &
  BetterResultMethods<ApplyExtension<E, M, T, "methods">, Err>;

export interface BetterResultHelpers<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  Err,
> {
  /** The `db` this view wraps, for everything that returns plain results. */
  readonly $db: Db<M, F, E, C>;
  /** Converts any `AsyncResult`, such as one from a plugin method or `$with`. */
  $from<T>(result: AsyncResult<T>): Out<T, Err>;
  $rpc<N extends PlainName<F>>(
    name: N,
    ...rest: [...RpcArgs<F, N>, options: RawRpcOptions]
  ): Out<unknown, Err>;
  $rpc<N extends PlainName<F>, R = F[N]["Returns"]>(
    name: N,
    ...rest: [...RpcArgs<F, N>, options?: RpcOptions<R>]
  ): Out<R, Err>;
  $rpc<N extends OverloadedName<F>, const A extends F[N]["Args"]>(
    name: N,
    args: OverloadArgs<F[N], A>,
    options: RawRpcOptions,
  ): Out<unknown, Err>;
  $rpc<
    N extends OverloadedName<F>,
    const A extends F[N]["Args"],
    R = OverloadReturns<F[N], A>,
  >(
    name: N,
    args: OverloadArgs<F[N], A>,
    options?: RpcOptions<R>,
  ): Out<R, Err>;
  $rpc<N extends NoArgName<F>>(
    name: N,
  ): Out<OverloadReturns<F[N], Record<never, never>>, Err>;
  $table<T extends TableKey<M>>(
    name: T,
  ): BetterResultRepositoryOf<M, T, E, Err>;
  $run<S extends QuerySpec<TableKey<M>>>(
    spec: S,
    options?: { readonly signal?: AbortSignal },
  ): Out<InferResult<S>, Err>;
  $many<S extends ReadSet>(
    readSet: S,
    params: InferReadSetParams<S>,
    options?: { readonly signal?: AbortSignal },
  ): Out<ReadSetResult<S>, Err>;
  $many<const S extends readonly QuerySpec<TableKey<M>>[]>(
    specs: S,
    options?: { readonly signal?: AbortSignal },
  ): Out<{ -readonly [K in keyof S]: InferResult<S[K]> }, Err>;
  $search<T extends TableKey<M>, const A extends SearchArgs<M, T>>(
    table: T,
    args: A,
  ): Out<(Payload<M, T, A> & SearchScore<A>)[], Err>;
  /** Runs a list query (`defineListQuery`) like `list.run(db, query, extra)`. */
  $list<
    T extends TableKey<M>,
    S extends string,
    LF extends string,
    LC extends boolean,
    P extends ListPagination,
    const A extends ListExtra<M, T> & FindExt<E, M, T>,
  >(
    list: ListDefinition<M, T, E, S, LF, LC, P>,
    query: ListQuery<S, LF>,
    extra?: A,
  ): Out<ListPage<Payload<M, T, A>, LF, LC, P>, Err>;
}

/** A `db` whose repositories and helpers return better-result values. */
export type BetterResultDb<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  Err,
> = {
  readonly [T in TableKey<M>]: BetterResultRepositoryOf<M, T, E, Err>;
} & BetterResultHelpers<M, F, E, C, Err>;

type Convert = (result: AsyncResult<unknown>) => unknown;

type Callable = (...args: unknown[]) => unknown;

const HELPERS = ["$rpc", "$run", "$many", "$search"] as const;

function converterOf(toResult: BetterResultConverter): Convert {
  if (typeof toResult === "function") {
    return (result) => toResult(result);
  }

  return (result) => toBetterResult(result, toResult.Result, toResult.mapError);
}

/** The parts of a `db` the view reads; tables come from `$table`. */
interface DbLike {
  $table(name: string): unknown;
  readonly $rpc: unknown;
  readonly $run: unknown;
  readonly $many: unknown;
  readonly $search: unknown;
}

function view(db: DbLike, convert: Convert): object {
  const wrap = (value: unknown): unknown =>
    value instanceof AsyncResult ? convert(value) : value;

  const call = (target: object, method: unknown, name: string): Callable => {
    if (typeof method !== "function") {
      throw new TypeError(`better-supabase: ${name} is not a function`);
    }

    return (...args) => wrap(method.apply(target, args));
  };

  const repositories = new WeakMap<object, object>();

  const repository = (target: unknown, name: string): object => {
    if (typeof target !== "object" || target === null) {
      throw new TypeError(`better-supabase: unknown table ${name}`);
    }

    const cached = repositories.get(target);

    if (cached) {
      return cached;
    }

    const wrapped = Object.fromEntries(
      Object.entries(target).map(([key, value]) => [
        key,
        typeof value === "function" ? call(target, value, key) : value,
      ]),
    );

    repositories.set(target, wrapped);

    return wrapped;
  };

  const result: Record<string, unknown> = {
    $db: db,
    $from: convert,
    $table: (name: string): object => repository(db.$table(name), name),
    $list: (
      list: { run(db: object, query: unknown, extra?: unknown): unknown },
      query: unknown,
      extra?: unknown,
    ): unknown => wrap(list.run(db, query, extra)),
  };

  for (const key of HELPERS) {
    result[key] = call(db, db[key], `db.${key}`);
  }

  for (const key in db) {
    if (key.startsWith("$")) {
      continue;
    }

    Object.defineProperty(result, key, {
      enumerable: true,
      get: () => repository(db.$table(key), key),
    });
  }

  return result;
}

/**
 * A view of `db` whose repository methods, `$rpc`, `$run`, `$many`, `$search`
 * and list queries (`$list`) return better-result `Result` values. `toResult`
 * is a `defineBetterResultErrors` converter or `{ Result, mapError }`. `db`
 * itself is unchanged, and `$db` returns it.
 *
 * ```ts
 * import { Result, TaggedError } from "better-result";
 * import { defineBetterResultErrors } from "better-supabase";
 * import { withBetterResult } from "better-supabase/better-result";
 *
 * const toResult = defineBetterResultErrors(
 *   Result,
 *   { not_found: NotFound },
 *   DbFailure,
 * );
 * const rdb = withBetterResult(db, toResult);
 * const customer = await rdb.customers.findById(id); // Result<Customer, NotFound | DbFailure>
 * ```
 */
export function withBetterResult<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  const X extends BetterResultConverter,
>(
  db: Db<M, F, E, C>,
  toResult: X,
): BetterResultDb<M, F, E, C, ConvertedError<X>> {
  // SAFETY: a Db has $table for every table key plus the $rpc, $run, $many and $search helpers.
  const source = db as DbLike;

  // SAFETY: view() wraps every repository method and helper the type lists, converting each AsyncResult with toResult.
  return view(source, converterOf(toResult)) as BetterResultDb<
    M,
    F,
    E,
    C,
    ConvertedError<X>
  >;
}
