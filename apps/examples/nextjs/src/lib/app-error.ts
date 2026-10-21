import type { DbError } from "better-supabase";
import type { BetterResultMapping } from "better-supabase/better-result";

import { Result } from "better-result";

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

/**
 * For `withBetterResult(db, appErrors)`: better-result values with an
 * `AppError`.
 */
export const appErrors: BetterResultMapping<AppError> = {
  Result,
  mapError: toAppError,
};
