import type { DbError, DbErrorKind } from "./errors.ts";

/** Thrown by `.orThrow()`. Carries the plain `DbError` as `error`. */
export class DbException extends Error {
  override readonly name = "DbException";
  readonly error: DbError;

  constructor(error: DbError) {
    super(error.message);
    this.error = error;
  }

  get kind(): DbErrorKind {
    return this.error.kind;
  }
}
