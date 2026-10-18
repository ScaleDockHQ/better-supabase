import type { RawDbError } from "../core/errors.ts";

interface PgErrorLike {
  readonly code?: string;
  readonly message?: string;
  readonly detail?: string;
  readonly hint?: string;
  readonly constraint?: string;
  readonly column?: string;
  readonly table?: string;
  /** `@supabase/server`'s `PostgresPoolError` puts `retryAfterMs` here. */
  readonly details?: unknown;
}

function isPgError(value: unknown): value is PgErrorLike {
  // SAFETY: value is a non-null object here, and the code field is checked before use.
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as PgErrorLike).code === "string"
  );
}

function retryAfterMsOf(details: unknown): number | undefined {
  if (
    typeof details !== "object" ||
    details === null ||
    !("retryAfterMs" in details)
  ) {
    return undefined;
  }

  const value = details.retryAfterMs;

  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

/** node-postgres error fields to the shape `mapDbError` reads. */
export function fromPgError(error: unknown): RawDbError | undefined {
  if (!isPgError(error)) {
    return undefined;
  }

  const raw: { -readonly [K in keyof RawDbError]: RawDbError[K] } = {};

  if (error.code !== undefined) {
    raw.code = error.code;
  }

  if (error.message !== undefined) {
    raw.message = error.message;
  }

  if (error.detail !== undefined) {
    raw.details = error.detail;
  }

  if (error.hint !== undefined) {
    raw.hint = error.hint;
  }

  if (error.constraint !== undefined) {
    raw.constraint = error.constraint;
  }

  if (error.column !== undefined) {
    raw.column = error.column;
  }

  if (error.table !== undefined) {
    raw.table = error.table;
  }

  const retryAfterMs = retryAfterMsOf(error.details);

  if (retryAfterMs !== undefined) {
    raw.retryAfterMs = retryAfterMs;
  }

  return raw;
}
