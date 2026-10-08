import type { AuthState } from "../auth/resolve.ts";
import type { DbError } from "../core/errors.ts";

import { dbErrorOf } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { type KitRequireOptions, requireCaller } from "./kit.ts";
import { defaultExpose } from "./respond.ts";

/** Where refused callers go instead of a Problem Details response. */
export interface RefusalRedirects {
  /** Sign-in page for callers without a session; gets `?next=<path>`. */
  readonly signIn?: string;
  /** Second-factor page for users below the route's `aal`; gets `?next=<path>`. */
  readonly mfa?: string;
}

function isAalRefusal(error: DbError): boolean {
  return (
    error.kind === "forbidden" &&
    "required" in error &&
    error.required === "aal2"
  );
}

/** The page a refused caller is sent to, with `?next=`, when one is configured. */
export function refusalTarget(
  error: DbError,
  request: Request,
  redirects: RefusalRedirects,
): URL | undefined {
  const page =
    error.kind === "unauthorized"
      ? redirects.signIn
      : isAalRefusal(error)
        ? redirects.mfa
        : undefined;
  if (page === undefined) return undefined;
  const url = new URL(request.url);
  const target = new URL(page, url);
  if (target.pathname === url.pathname) return undefined;
  target.searchParams.set("next", `${url.pathname}${url.search}`);
  return target;
}

/** A refusal as a redirect to `signIn` or `mfa`, else Problem Details. */
export function refusalResponse(
  error: DbError,
  request: Request,
  redirects: RefusalRedirects,
  expose: boolean,
): Response {
  const target = refusalTarget(error, request, redirects);
  if (target) {
    return new Response(null, {
      status: 303,
      headers: { location: target.href },
    });
  }
  return problemResponse(error, {
    instance: new URL(request.url).pathname,
    expose,
  });
}

/** What a route guard reads: the request's contributions. */
export interface GuardedLocals {
  readonly bs: { readonly auth: AuthState };
  readonly tenant?: string | undefined;
}

export interface RouteGuardOptions<C = unknown, P = unknown>
  extends KitRequireOptions<C, P>, RefusalRedirects {
  /** Include internal error messages in Problem Details. Defaults to development only. */
  readonly expose?: boolean;
}

/** The refusal for a caller `options` refuses, or `undefined` to let it through. */
export async function routeRefusal(
  locals: GuardedLocals,
  request: Request,
  options: RouteGuardOptions,
): Promise<Response | undefined> {
  const caller = await requireCaller(locals.bs.auth, options, locals.tenant);
  if (!("kind" in caller)) return undefined;
  return refusalResponse(
    caller,
    request,
    options,
    options.expose ?? defaultExpose(),
  );
}

/**
 * An `onError` mapper: a thrown `DbException` (or an error caused by a
 * `DbError`) becomes Problem Details; anything else is `undefined`, so the
 * framework's own handling stays.
 */
export function errorResponse(
  cause: unknown,
  request: Request,
  options: { readonly expose?: boolean } = {},
): Response | undefined {
  const found = dbErrorOf(cause);
  if (!found) return undefined;
  return problemResponse(found, {
    instance: new URL(request.url).pathname,
    expose: options.expose ?? defaultExpose(),
  });
}

/** Reads the guard's view of a request's contributions; throws without `withBetterSupabase`. */
export function guardedLocals(contributions: object): GuardedLocals {
  const bs: unknown = "bs" in contributions ? contributions.bs : undefined;
  if (typeof bs !== "object" || bs === null || !("auth" in bs)) {
    throw new Error(
      "better-supabase: the route guard needs withBetterSupabase(server) in the entries",
    );
  }
  const tenant: unknown =
    "tenant" in contributions ? contributions.tenant : undefined;
  return {
    // SAFETY: withBetterSupabase is the only entry that contributes `bs.auth`, and it is an AuthState.
    bs: bs as GuardedLocals["bs"],
    tenant: typeof tenant === "string" ? tenant : undefined,
  };
}
