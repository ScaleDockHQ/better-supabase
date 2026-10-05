import {
  type DbError,
  type DbErrorKind,
  type DbErrorOf,
  DbException,
  dbError,
  dbErrorOf,
} from "./errors.ts";

/** Turns a `DbError` into the error `.orThrow()` throws; set with `betterSupabase.mapError()`. */
export type ThrowMapper = (error: DbError) => unknown;

const throwMappers = new WeakMap<AsyncResult<unknown>, ThrowMapper>();

function inherit<T>(
  from: AsyncResult<unknown>,
  next: AsyncResult<T>,
): AsyncResult<T> {
  const mapper = throwMappers.get(from);
  if (mapper) throwMappers.set(next, mapper);
  return next;
}

/** Marks `result` so its `.orThrow()` throws `mapper(error)`; returns it. */
export function withErrorMapper<T>(
  result: AsyncResult<T>,
  mapper: ThrowMapper,
): AsyncResult<T> {
  throwMappers.set(result, mapper);
  return result;
}

export type Ok<T> = {
  readonly ok: true;
  readonly data: T;
  readonly error: null;
};
export type Err<E = DbError> = {
  readonly ok: false;
  readonly data: null;
  readonly error: E;
};
export type Result<T, E = DbError> = Ok<T> | Err<E>;

export function ok<T>(data: T): Ok<T> {
  return { ok: true, data, error: null };
}

export function err<E = DbError>(error: E): Err<E> {
  return { ok: false, data: null, error };
}

/**
 * A lazy-free `PromiseLike<Result<T>>` with helpers. `await` gives the
 * `Result`; `.orThrow()` gives the data or throws a `DbException`.
 */
export class AsyncResult<T> implements PromiseLike<Result<T>> {
  readonly #promise: Promise<Result<T>>;

  constructor(promise: Promise<Result<T>>) {
    this.#promise = promise.catch((cause: unknown) => err(toDbError(cause)));
  }

  static from<T>(run: () => Promise<Result<T>>): AsyncResult<T> {
    return new AsyncResult(Promise.resolve().then(run));
  }

  static ok<T>(data: T): AsyncResult<T> {
    return new AsyncResult(Promise.resolve(ok(data)));
  }

  static err<T = never>(error: DbError): AsyncResult<T> {
    return new AsyncResult<T>(Promise.resolve(err(error)));
  }

  // oxlint-disable-next-line unicorn/no-thenable -- `await` on an AsyncResult yields its Result by design
  then<R1 = Result<T>, R2 = never>(
    onfulfilled?: ((value: Result<T>) => R1 | PromiseLike<R1>) | null,
    onrejected?: ((reason: unknown) => R2 | PromiseLike<R2>) | null,
  ): Promise<R1 | R2> {
    return this.#promise.then(onfulfilled, onrejected);
  }

  /**
   * Resolves with the data, or rejects with a `DbException`. Pass `factory`
   * to throw your own error instead, e.g. an HTTP error for your framework;
   * without it, the mapper from `betterSupabase.mapError()` applies when one is set.
   */
  async orThrow(factory?: (error: DbError) => unknown): Promise<T> {
    const result = await this.#promise;
    if (result.ok) return result.data;
    const mapper = factory ?? throwMappers.get(this);
    throw mapper ? mapper(result.error) : new DbException(result.error);
  }

  /** Resolves with the data, or `fallback` when the result is an error. */
  async unwrapOr<F>(fallback: F): Promise<T | F> {
    const result = await this.#promise;
    return result.ok ? result.data : fallback;
  }

  map<U>(fn: (data: T) => U): AsyncResult<U> {
    return inherit(
      this,
      new AsyncResult(
        this.#promise.then((result) =>
          result.ok ? ok(fn(result.data)) : result,
        ),
      ),
    );
  }

  mapError(fn: (error: DbError) => DbError): AsyncResult<T> {
    return inherit(
      this,
      new AsyncResult(
        this.#promise.then((result) =>
          result.ok ? result : err(fn(result.error)),
        ),
      ),
    );
  }

  andThen<U>(fn: (data: T) => PromiseLike<Result<U>>): AsyncResult<U> {
    return inherit(
      this,
      new AsyncResult(
        this.#promise.then((result) => (result.ok ? fn(result.data) : result)),
      ),
    );
  }
}

/** What `toBetterResult` returns: the `status`/`value`/`error` fields every better-result value has. */
export type BetterResultValue<T, E> =
  | { readonly status: "ok"; readonly value: T }
  | { readonly status: "error"; readonly error: E };

/** The part of better-result's `Result` namespace `toBetterResult` calls. */
export interface BetterResultApi<T, E> {
  ok(value: NoInfer<T>): unknown;
  err(error: NoInfer<E>): unknown;
}

/** The value type of a better-result `Result` type. */
export type BetterResultOk<R> = R extends {
  readonly status: "ok";
  readonly value: infer T;
}
  ? T
  : never;

/** The error type of a better-result `Result` type. */
export type BetterResultErr<R> = R extends {
  readonly status: "error";
  readonly error: infer E;
}
  ? E
  : never;

/**
 * Builds a better-result value with the `Result` namespace you pass, so
 * better-result stays your dependency. Errors go through `mapError`, or, for a
 * result from a `db` of `betterSupabase.mapError(fn)`, through `fn` (typed `unknown`).
 *
 * The value is typed as better-result's `Result<T, E>` when the call has one
 * as its expected type (an annotation or a function's return type) or as its
 * type argument. That type is checked against the row type and `mapError`.
 * Without one, it is a `BetterResultValue<T, E>`.
 *
 * ```ts
 * import { Result } from 'better-result';
 * const customer: Result<Customer, AppError> = toBetterResult(
 *   await db.customers.findById(id),
 *   Result,
 *   toAppError,
 * );
 * ```
 */
export function toBetterResult<
  R extends BetterResultValue<unknown, unknown> = never,
>(
  result: Result<BetterResultOk<R>>,
  api: BetterResultApi<BetterResultOk<R>, BetterResultErr<R>>,
  mapError: (error: DbError) => BetterResultErr<R>,
): R;
export function toBetterResult<
  R extends BetterResultValue<unknown, unknown> = never,
>(
  result: Result<BetterResultOk<R>> &
    (DbError extends BetterResultErr<R> ? unknown : never),
  api: BetterResultApi<BetterResultOk<R>, DbError>,
): R;
export function toBetterResult<
  R extends BetterResultValue<unknown, unknown> = never,
>(
  result: AsyncResult<BetterResultOk<R>>,
  api: BetterResultApi<BetterResultOk<R>, BetterResultErr<R>>,
  mapError: (error: DbError) => BetterResultErr<R>,
): Promise<R>;
export function toBetterResult<
  R extends BetterResultValue<unknown, unknown> = never,
>(
  result: AsyncResult<BetterResultOk<R>> &
    (unknown extends BetterResultErr<R> ? unknown : never),
  api: BetterResultApi<BetterResultOk<R>, unknown>,
): Promise<R>;
export function toBetterResult<T, E>(
  result: Result<T>,
  api: BetterResultApi<T, E>,
  mapError: (error: DbError) => E,
): BetterResultValue<T, E>;
export function toBetterResult<T>(
  result: Result<T>,
  api: BetterResultApi<T, DbError>,
): BetterResultValue<T, DbError>;
export function toBetterResult<T, E>(
  result: AsyncResult<T>,
  api: BetterResultApi<T, E>,
  mapError: (error: DbError) => E,
): Promise<BetterResultValue<T, E>>;
export function toBetterResult<T>(
  result: AsyncResult<T>,
  api: BetterResultApi<T, unknown>,
): Promise<BetterResultValue<T, unknown>>;
export function toBetterResult(
  result: Result<unknown> | AsyncResult<unknown>,
  api: BetterResultApi<unknown, unknown>,
  mapError?: ThrowMapper,
): unknown {
  const build = (settled: Result<unknown>, mapper?: ThrowMapper): unknown =>
    settled.ok
      ? api.ok(settled.data)
      : api.err(mapper ? mapper(settled.error) : settled.error);
  if (result instanceof AsyncResult) {
    const mapper = mapError ?? throwMappers.get(result);
    return result.then((settled) => build(settled, mapper));
  }
  return build(result, mapError);
}

/**
 * An error class for one `DbError` kind. better-result's
 * `class NotFound extends TaggedError("NotFound")<{ message: string; error: DbError }> {}`
 * fits, as does any class whose constructor takes `{ message, error }`.
 */
export type DbErrorClass<K extends DbErrorKind = DbErrorKind> = new (props: {
  readonly message: string;
  readonly error: DbErrorOf<K>;
}) => unknown;

/** Error classes by `DbError` kind; kinds left out use the fallback class. */
export type DbErrorClasses = { readonly [K in DbErrorKind]?: DbErrorClass<K> };

/** The error a `DbError` of kind `K` becomes. */
export type MappedDbError<
  M extends DbErrorClasses,
  F extends DbErrorClass,
  K extends DbErrorKind = DbErrorKind,
> = K extends keyof M
  ? M[K] extends abstract new (...args: never[]) => infer I
    ? I
    : F extends abstract new (...args: never[]) => infer I
      ? I
      : never
  : F extends abstract new (...args: never[]) => infer I
    ? I
    : never;

/**
 * Converts results with a fixed `Result` namespace and error mapping. Like
 * `toBetterResult`, the value is typed as better-result's `Result<T, E>`
 * when the call has one as its expected type, and `E` must accept every
 * error the mapping returns.
 */
export interface BetterResultErrors<
  M extends DbErrorClasses,
  F extends DbErrorClass,
> {
  <R extends BetterResultValue<unknown, unknown> = never>(
    result: Result<BetterResultOk<R>> &
      (MappedDbError<M, F> extends BetterResultErr<R> ? unknown : never),
  ): R;
  <R extends BetterResultValue<unknown, unknown> = never>(
    result: AsyncResult<BetterResultOk<R>> &
      (MappedDbError<M, F> extends BetterResultErr<R> ? unknown : never),
  ): Promise<R>;
  <T>(result: Result<T>): BetterResultValue<T, MappedDbError<M, F>>;
  <T>(
    result: AsyncResult<T>,
  ): Promise<BetterResultValue<T, MappedDbError<M, F>>>;
  /** The error instance for one `DbError`, typed by its kind. */
  map<E extends DbError>(error: E): MappedDbError<M, F, E["kind"]>;
}

/**
 * A typed mapping from `DbError` kinds to error classes, usually
 * better-result `TaggedError` classes, bound to better-result's `Result`
 * namespace. Kinds without a class use `fallback`. Each instance gets the
 * error's `message` and the `DbError` itself as `error`.
 *
 * ```ts
 * import { Result, TaggedError } from 'better-result';
 * class NotFound extends TaggedError('NotFound')<{ message: string; error: DbError }> {}
 * class DbFailure extends TaggedError('DbFailure')<{ message: string; error: DbError }> {}
 * const toResult = defineBetterResultErrors(Result, { not_found: NotFound }, DbFailure);
 * const customer: Result<Customer, NotFound | DbFailure> = await toResult(db.customers.findById(id));
 * ```
 */
export function defineBetterResultErrors<
  const M extends DbErrorClasses,
  F extends DbErrorClass,
>(
  api: BetterResultApi<unknown, unknown>,
  classes: M,
  fallback: F,
): BetterResultErrors<M, F> {
  const map = (error: DbError): unknown => {
    // SAFETY: classes[kind] is the class for that kind, so it takes this error.
    const Class = (classes[error.kind] ?? fallback) as DbErrorClass;
    return new Class({ message: error.message, error });
  };
  const convert = (result: Result<unknown> | AsyncResult<unknown>): unknown =>
    result instanceof AsyncResult
      ? toBetterResult(result, api, map)
      : toBetterResult(result, api, map);
  // SAFETY: convert implements every call signature; map returns the class for the error's kind.
  return Object.assign(convert, { map }) as BetterResultErrors<M, F>;
}

/**
 * Converts a better-result value back into a `Result`, by its `status`
 * field, so it works across better-result versions. A `DbError`, or an
 * error whose `cause` is one, is kept; others go through `mapError`
 * (default `toDbError`).
 */
export function fromBetterResult<T>(
  result: BetterResultValue<T, unknown>,
  mapError: (error: unknown) => DbError = toDbError,
): Result<T> {
  switch (result.status) {
    case "ok":
      return ok(result.value);
    case "error":
      return err(dbErrorOf(result.error) ?? mapError(result.error));
    default: {
      const never: never = result;
      throw new TypeError(
        `better-supabase: fromBetterResult() expects a better-result value, got ${String(never)}`,
      );
    }
  }
}

export function toDbError(cause: unknown): DbError {
  if (cause instanceof DbException) return cause.error;
  if (cause instanceof Error && cause.name === "AbortError") {
    return dbError("aborted", cause.message || "The operation was aborted");
  }
  const message = cause instanceof Error ? cause.message : String(cause);
  return dbError("unexpected", message);
}
