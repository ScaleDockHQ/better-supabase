import type { AuthState } from "../auth/resolve.ts";

import { actorOf, delegationOf } from "../auth/actor.ts";
import { type Aal, checkAal } from "../auth/mfa.ts";
import { type DbError, dbError, dbErrorOf, isDbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { toDbError } from "../core/result.ts";

export type AuthKind = AuthState["kind"];

export interface GuardOptions {
  /** Auth kinds allowed through. Defaults to `['user']`. */
  readonly allow?: readonly Exclude<AuthKind, "invalid">[];
  /**
   * Assurance level user sessions need. `aal2` answers 403 with
   * `required: 'aal2'` until the user verifies a second factor.
   */
  readonly aal?: Aal;
  /**
   * OAuth scopes a delegated token (an OAuth client or an `act` chain) needs.
   * A missing one answers 403 with `error="insufficient_scope"`. The user's
   * own session is not limited by scopes.
   */
  readonly scopes?: readonly string[];
}

/** Guard options for middleware and fetch handlers that resolve the caller themselves. */
export interface MiddlewareOptions extends GuardOptions {
  /**
   * Refresh an expired cookie session and send the new cookies. Only for
   * routes browsers call with cookies; bearer tokens never refresh.
   */
  readonly refresh?: boolean;
}

/** The scopes a delegated user token lacks; empty for the user's own session. */
function missingScopes(
  auth: Extract<AuthState, { kind: "user" }>,
  required: readonly string[],
): readonly string[] {
  if (required.length === 0) return [];
  const outcome = actorOf(auth.claims);
  if (!outcome.ok || !outcome.actor) return [];
  const granted = new Set(delegationOf(auth.claims)?.scopes);
  return required.filter((scope) => !granted.has(scope));
}

/** `undefined` when `auth` may pass; otherwise the 401/403 error to send. */
// SAFETY: includes only compares values, so any auth kind is safe to look up.
export function guard(
  auth: AuthState,
  allow: GuardOptions["allow"] = ["user"],
  aal: Aal = "aal1",
  scopes: readonly string[] = [],
): DbError | undefined {
  if (auth.kind === "invalid") return auth.error;
  if ((allow as readonly AuthKind[]).includes(auth.kind)) {
    const denied = checkAal(auth, aal);
    if (denied || auth.kind !== "user") return denied;
    const missing = missingScopes(auth, scopes);
    return missing.length > 0
      ? dbError("forbidden", `The token lacks the scope ${missing.join(" ")}`, {
          code: "INSUFFICIENT_SCOPE",
          scopes,
        })
      : undefined;
  }
  return auth.kind === "anon"
    ? dbError("unauthorized", "Sign in to continue", {
        code: "MISSING_CREDENTIALS",
      })
    : dbError("forbidden", `A ${auth.kind} caller is not allowed here`);
}

export function isResult(
  value: unknown,
): value is { ok: boolean; data: unknown; error: unknown } {
  return (
    typeof value === "object" &&
    value !== null &&
    "ok" in value &&
    "data" in value &&
    "error" in value
  );
}

export type Settled =
  | { readonly ok: true; readonly data: unknown }
  | { readonly ok: false; readonly error: DbError };

/**
 * Settles a handler's return value: `Result`s and `AsyncResult`s unwrap,
 * thrown `DbException`s (or errors whose `cause` is a `DbError`) become
 * errors, anything else is data. Other thrown
 * errors propagate.
 */
export async function settle(run: () => unknown): Promise<Settled> {
  try {
    const value: unknown = await run();
    if (!isResult(value)) return { ok: true, data: value };
    if (value.ok) return { ok: true, data: value.data };
    return {
      ok: false,
      error: isDbError(value.error) ? value.error : toDbError(value.error),
    };
  } catch (cause) {
    const thrown = dbErrorOf(cause);
    if (thrown) return { ok: false, error: thrown };
    throw cause;
  }
}

export interface RespondOptions {
  readonly instance?: string;
  readonly expose?: boolean;
  /** Status for data responses. Defaults to 200 (204 without data). */
  readonly status?: number;
}

/** A handler's value as a response: `Response` as is, data as JSON, errors as Problem Details. */
export async function respond(
  run: () => unknown,
  options: RespondOptions = {},
): Promise<Response> {
  const settled = await settle(run);
  if (!settled.ok) return problemResponse(settled.error, options);
  if (settled.data instanceof Response) return settled.data;
  if (settled.data === undefined) return new Response(null, { status: 204 });
  return Response.json(settled.data, { status: options.status ?? 200 });
}

export function defaultExpose(): boolean {
  return (
    // oxlint-disable-next-line typescript/prefer-optional-chain -- `process?.env` throws where `process` is undeclared.
    typeof process !== "undefined" && process.env["NODE_ENV"] === "development"
  );
}
