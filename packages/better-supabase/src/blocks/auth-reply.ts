import type { Result } from "../core/result.ts";

import { type DbError, dbError } from "../core/errors.ts";
import { err, ok, toDbError } from "../core/result.ts";

/** A supabase-js Auth answer: `data` or an `AuthError`. */
export type AuthReply<T> =
  | { readonly data: T; readonly error: null }
  | { readonly data: null; readonly error: object };

interface AuthFailure {
  readonly message?: unknown;
  readonly name?: unknown;
  readonly status?: unknown;
  readonly code?: unknown;
}

/** An `AuthError` from the Auth API as a `DbError`, keeping its code. */
function authFailure(error: object): DbError {
  // SAFETY: every AuthFailure field is optional and type-checked below.
  const failure = error as AuthFailure;
  const message =
    typeof failure.message === "string" && failure.message !== ""
      ? failure.message
      : "Auth request failed";
  const status = typeof failure.status === "number" ? failure.status : 0;
  const base = typeof failure.code === "string" ? { code: failure.code } : {};
  if (failure.name === "AuthRetryableFetchError" || status >= 500) {
    return dbError("network", message, base);
  }
  switch (status) {
    case 400:
    case 422: {
      return dbError("invalid_input", message, base);
    }
    case 401: {
      return dbError("unauthorized", message, base);
    }
    case 403: {
      return dbError("forbidden", message, base);
    }
    case 404: {
      return dbError("not_found", message, base);
    }
    case 429: {
      return dbError("rate_limited", message, base);
    }
    default: {
      return dbError("unexpected", message, base);
    }
  }
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
