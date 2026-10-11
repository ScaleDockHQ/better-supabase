import { forbidden } from "next/dist/client/components/forbidden.js";
import { notFound } from "next/dist/client/components/not-found.js";
import { unauthorized } from "next/dist/client/components/unauthorized.js";

import { DbException, type DbError } from "../core/errors.ts";

/** Whether `cause` is one of Next's own control-flow errors (they carry a `digest`). */
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
    if (isNextInterrupt(cause)) throw cause;
  }
  notFound();
}

/** The Next.js interrupt for a refused Server Component render. */
export function interrupt(error: DbError): never {
  if (error.kind === "unauthorized") authInterrupt(unauthorized);
  if (error.kind === "forbidden") authInterrupt(forbidden);
  if (error.kind === "not_found") notFound();
  throw new DbException(error);
}

const NEXT_DIGESTS: ReadonlySet<string> = new Set([
  "NEXT_REDIRECT",
  "NEXT_HTTP_ERROR_FALLBACK",
  "DYNAMIC_SERVER_USAGE",
  "BAILOUT_TO_CLIENT_SIDE_RENDERING",
  "HANGING_PROMISE_REJECTION",
  "NEXT_PRERENDER_INTERRUPTED",
]);

const REACT_POSTPONE = Symbol.for("react.postpone");

/**
 * `unstable_rethrow` without `next/navigation`: that entry loads the client
 * router context, which Turbopack can't resolve inside route handlers. The
 * digests are the ones Next 16 checks.
 */
export function rethrowNextControlFlow(error: unknown): void {
  if (typeof error !== "object" || error === null) return;
  const digest = "digest" in error ? error.digest : undefined;
  if (
    (typeof digest === "string" &&
      NEXT_DIGESTS.has(digest.split(";", 1)[0] ?? "")) ||
    ("$$typeof" in error && error.$$typeof === REACT_POSTPONE) ||
    (error instanceof Error &&
      error.message.includes("needs to bail out of prerendering"))
  ) {
    // oxlint-disable-next-line typescript/only-throw-error -- React's postpone signal is not an Error, and Next needs the original value.
    throw error;
  }
  if ("cause" in error) rethrowNextControlFlow(error.cause);
}
