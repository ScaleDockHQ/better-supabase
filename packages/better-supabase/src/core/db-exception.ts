import type { DbError, DbErrorKind } from "./errors.ts";

/**
 * Thrown by `.orThrow()`. Carries the plain `DbError` as `error` and as
 * `cause`, and copies its `kind`, `code`, `status`, `details`, `hint` and
 * `table` onto the exception, so error trackers and `catch` blocks that only
 * read an error's own fields see them.
 */
export class DbException extends Error {
  override readonly name = "DbException";
  readonly error: DbError;
  readonly kind: DbErrorKind;
  /** Suggested HTTP status. */
  readonly status: number;
  /** SQLSTATE or PostgREST code (`23505`, `PGRST116`), when known. */
  declare readonly code?: string;
  declare readonly details?: string;
  /** Postgres `HINT`. `raised` errors use it as an app-level error code. */
  declare readonly hint?: string;
  /** App-cased table key the operation ran against. */
  declare readonly table?: string;
  declare readonly cause: DbError;

  constructor(error: DbError) {
    super(error.message, { cause: error });
    this.error = error;
    this.kind = error.kind;
    this.status = error.status;

    for (const key of ["code", "details", "hint", "table"] as const) {
      if (error[key] !== undefined) {
        Object.defineProperty(this, key, {
          value: error[key],
          enumerable: true,
        });
      }
    }
  }
}
