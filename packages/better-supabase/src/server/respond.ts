import type { AuthState } from "../auth/resolve.ts";
import type { RefreshPolicy } from "./refresh.ts";

import { actorOf, delegationOf } from "../auth/actor.ts";
import { type Aal, checkAal } from "../auth/mfa.ts";
import { isAnonymousUser } from "../auth/view.ts";
import { type DbError, dbError, dbErrorOf, isDbError } from "../core/errors.ts";
import { jsonResponse } from "../core/json.ts";
import { problemResponse } from "../core/problem.ts";
import { toDbError } from "../core/result.ts";

export type AuthKind = AuthState["kind"];

/**
 * An auth kind a guard lets through. `anonymous` admits users signed in with
 * `signInAnonymously()` (`is_anonymous`); `anon` admits callers without a
 * session only.
 */
export type AllowedCaller = Exclude<AuthKind, "invalid"> | "anonymous";

export interface GuardOptions {
  /**
   * Callers allowed through. Defaults to `['user']`, which refuses anonymous
   * sign-ins. Only `'anonymous'` admits them: `['anonymous']` alone admits
   * anonymous sign-ins and refuses other users, and `'anon'` (no session)
   * never admits them.
   */
  readonly allow?: readonly AllowedCaller[];
  /**
   * Assurance level user sessions need. `aal2` answers 403 with
   * `required: 'aal2'` until the user verifies a second factor.
   */
  readonly aal?: Aal;
  /**
   * OAuth scopes a delegated token (an OAuth client or an `act` chain) or an
   * API key needs. A missing one answers 403 with `error="insufficient_scope"`.
   * The user's own session is not limited by scopes.
   */
  readonly scopes?: readonly string[];
}

/** Guard options for middleware and fetch handlers that resolve the caller themselves. */
export interface MiddlewareOptions extends GuardOptions {
  /**
   * Refresh an expired cookie session and send the new cookies. Only for
   * routes browsers call with cookies; bearer tokens never refresh.
   * `'navigation'` refreshes page loads and form posts only (`shouldRefresh`).
   */
  readonly refresh?: RefreshPolicy;
}

/**
 * The scopes a delegated user token lacks. Empty for the user's own session,
 * which a support or impersonated session counts as: only an `oauth-client`
 * actor is limited to what the user delegated.
 */
function missingScopes(
  auth: Extract<AuthState, { kind: "user" }>,
  required: readonly string[],
): readonly string[] {
  if (required.length === 0) return [];
  const outcome = actorOf(auth.claims);
  if (!outcome.ok || outcome.actor?.kind !== "oauth-client") return [];
  const granted = new Set(delegationOf(auth.claims)?.scopes);
  return required.filter((scope) => !granted.has(scope));
}

/** An API key's `*` scope grants every scope. */
function missingKeyScopes(
  granted: readonly string[],
  required: readonly string[],
): readonly string[] {
  if (granted.includes("*")) return [];
  return required.filter((scope) => !granted.includes(scope));
}

/** `undefined` when `auth` may pass; otherwise the 401/403 error to send. */
export function guard(
  auth: AuthState,
  allow: GuardOptions["allow"] = ["user"],
  aal: Aal = "aal1",
  scopes: readonly string[] = [],
): DbError | undefined {
  if (auth.kind === "invalid") return auth.error;
  const anonymous = auth.kind === "user" && isAnonymousUser(auth.claims);
  if (anonymous ? allow.includes("anonymous") : allow.includes(auth.kind)) {
    const denied = checkAal(auth, aal);
    if (denied) return denied;
    if (auth.kind !== "user" && auth.kind !== "apiKey") return undefined;
    const missing =
      auth.kind === "apiKey"
        ? missingKeyScopes(auth.scopes, scopes)
        : missingScopes(auth, scopes);
    return missing.length > 0
      ? dbError("forbidden", `The token lacks the scope ${missing.join(" ")}`, {
          code: "INSUFFICIENT_SCOPE",
          scopes,
        })
      : undefined;
  }
  if (anonymous) {
    return dbError("forbidden", "Sign up to continue", {
      code: "ANONYMOUS_USER",
    });
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
  return jsonResponse(settled.data, { status: options.status ?? 200 });
}

/** Prefetching the JWKS would add a network call to every test that builds a server. */
export function defaultPrefetchJwks(): boolean {
  // oxlint-disable-next-line typescript/prefer-optional-chain -- `process?.env` throws where `process` is undeclared.
  return typeof process === "undefined" || process.env["NODE_ENV"] !== "test";
}

export function defaultExpose(): boolean {
  return (
    // oxlint-disable-next-line typescript/prefer-optional-chain -- `process?.env` throws where `process` is undeclared.
    typeof process !== "undefined" && process.env["NODE_ENV"] === "development"
  );
}
