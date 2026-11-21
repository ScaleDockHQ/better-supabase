import {
  forbidden,
  notFound,
  unauthorized,
  unstable_rethrow as nextRethrow,
} from "next/navigation.js";

import type { DbError } from "../core/errors.ts";

import { DbException } from "../core/errors.ts";

/**
 * Whether `cause` is one of Next's own control-flow errors (they carry a
 * `digest`).
 */
function isNextInterrupt(cause: unknown): boolean {
  return (
    cause instanceof Error &&
    "digest" in cause &&
    typeof cause.digest === "string"
  );
}

/**
 * `unauthorized()` and `forbidden()` throw a plain error without
 * `experimental.authInterrupts`; `notFound()` is the fallback then.
 */
function authInterrupt(fn: () => never): never {
  try {
    fn();
  } catch (cause) {
    if (isNextInterrupt(cause)) {
      throw cause;
    }
  }

  notFound();
}

/** The Next.js interrupt for a refused Server Component render. */
export function interrupt(error: DbError): never {
  if (error.kind === "unauthorized") {
    authInterrupt(unauthorized);
  }

  if (error.kind === "forbidden") {
    authInterrupt(forbidden);
  }

  if (error.kind === "not_found") {
    notFound();
  }

  throw new DbException(error);
}

/**
 * Rethrows Next's own control-flow errors (redirects, `notFound()`, dynamic
 * rendering bailouts, prerender interrupts) and returns for any other error.
 */
export function rethrowNextControlFlow(error: unknown): void {
  nextRethrow(error);
}
