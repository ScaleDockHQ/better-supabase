import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { authErrorKind } from "../auth/error-kind.ts";
import { dbError, dbErrorOfStatus } from "../core/errors.ts";
import { err, ok, toDbError } from "../core/result.ts";

/** A supabase-js Auth answer: `data` or an `AuthError`. */
export type AuthReply<T> =
  | { readonly data: T; readonly error: null }
  | { readonly data: null; readonly error: object };

interface AuthLinkError {
  readonly message?: unknown;
  readonly name?: unknown;
  readonly status?: unknown;
  readonly code?: unknown;
}

/** An `AuthError` from the Auth API as a `DbError`, keeping its code. */
function authFailure(error: object): DbError {
  // SAFETY: every AuthLinkError field is optional and type-checked below.
  const failure = error as AuthLinkError;

  const message =
    typeof failure.message === "string" && failure.message !== ""
      ? failure.message
      : "Auth request failed";

  const status = typeof failure.status === "number" ? failure.status : 0;
  const base = typeof failure.code === "string" ? { code: failure.code } : {};

  const kind = authErrorKind(error);

  if (kind === "retryable") {
    return dbError("network", message, base);
  }

  if (kind === "rate-limited") {
    return dbError("rate_limited", message, base);
  }

  return dbErrorOfStatus(status, message, base);
}

/** Awaits an Auth call as a `Result`; a throw becomes its `DbError` too. */
export async function authResult<T>(
  call: () => PromiseLike<AuthReply<T>>,
): Promise<Result<T>> {
  try {
    const reply = await call();

    return reply.error === null
      ? ok(reply.data)
      : err(authFailure(reply.error));
  } catch (cause) {
    return err(toDbError(cause));
  }
}
