import type { DbError } from "./errors.ts";

import { dbError } from "./errors.ts";

/**
 * The hint of the `conflict` error a write answers with when the row changed
 * after the caller read it (`expectedVersion` no longer matches).
 */
export const STALE_WRITE = "STALE_WRITE";

/**
 * The SQLSTATE a module raises `STALE_WRITE` with, so the error is a `conflict`
 * and not a `raised` one.
 */
export const STALE_WRITE_SQLSTATE = "BS409";

/**
 * What a caller read: the row's `updatedAt`, passed back as `expectedVersion`
 * on an update.
 */
export type ExpectedVersion = Temporal.Instant;

/** The error for a write whose `expectedVersion` no longer matches. */
export function staleWriteError(
  message = "The record changed since it was read",
): DbError {
  return dbError("conflict", message, { hint: STALE_WRITE });
}

/** Whether `error` is a `STALE_WRITE` conflict. */
export function isStaleWrite(error: DbError): boolean {
  return error.kind === "conflict" && error.hint === STALE_WRITE;
}
