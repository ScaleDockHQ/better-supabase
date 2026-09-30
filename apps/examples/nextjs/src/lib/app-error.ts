import { Result } from "better-result";
import {
  type DbError,
  type Result as DbResult,
  toBetterResult,
} from "better-supabase";

/**
 * The app's error type. `cause` keeps the `DbError`, so route handlers and
 * actions still answer with Problem Details.
 */
export class AppError extends Error {
  override readonly name = "AppError";
  readonly kind: DbError["kind"];

  constructor(error: DbError) {
    super(error.message, { cause: error });
    this.kind = error.kind;
  }
}

export const toAppError = (error: DbError): AppError => new AppError(error);

/** A database `Result` as a better-result value with an `AppError`. */
export function toAppResult<T>(result: DbResult<T>): Result<T, AppError> {
  // SAFETY: toBetterResult builds the value with the Result class passed in,
  // and toAppError maps every error to AppError.
  return toBetterResult(result, Result, toAppError) as Result<T, AppError>;
}
