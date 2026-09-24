import { type DbError, DbException, dbError } from './errors.ts';

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

  // oxlint-disable-next-line unicorn/no-thenable
  then<R1 = Result<T>, R2 = never>(
    onfulfilled?: ((value: Result<T>) => R1 | PromiseLike<R1>) | null,
    onrejected?: ((reason: unknown) => R2 | PromiseLike<R2>) | null,
  ): Promise<R1 | R2> {
    return this.#promise.then(onfulfilled, onrejected);
  }

  /**
   * Resolves with the data, or rejects with a `DbException`. Pass `factory`
   * to throw your own error instead, e.g. an HTTP error for your framework.
   */
  async orThrow(factory?: (error: DbError) => unknown): Promise<T> {
    const result = await this.#promise;
    if (result.ok) return result.data;
    throw factory ? factory(result.error) : new DbException(result.error);
  }

  /** Resolves with the data, or `fallback` when the result is an error. */
  async unwrapOr<F>(fallback: F): Promise<T | F> {
    const result = await this.#promise;
    return result.ok ? result.data : fallback;
  }

  map<U>(fn: (data: T) => U): AsyncResult<U> {
    return new AsyncResult(
      this.#promise.then((result) =>
        result.ok ? ok(fn(result.data)) : result,
      ),
    );
  }

  mapError(fn: (error: DbError) => DbError): AsyncResult<T> {
    return new AsyncResult(
      this.#promise.then((result) =>
        result.ok ? result : err(fn(result.error)),
      ),
    );
  }

  andThen<U>(fn: (data: T) => PromiseLike<Result<U>>): AsyncResult<U> {
    return new AsyncResult(
      this.#promise.then((result) => (result.ok ? fn(result.data) : result)),
    );
  }
}

export function toDbError(cause: unknown): DbError {
  if (cause instanceof DbException) return cause.error;
  if (cause instanceof Error && cause.name === 'AbortError') {
    return dbError('aborted', cause.message || 'The operation was aborted');
  }
  const message = cause instanceof Error ? cause.message : String(cause);
  return dbError('unexpected', message);
}
