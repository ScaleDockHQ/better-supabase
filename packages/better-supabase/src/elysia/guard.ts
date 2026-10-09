import type { AnyEntry } from "@supabase/middleware";

import type { ElysiaBridge } from "../bridges/elysia.ts";
import type { RouteGuardOptions } from "../server/refusal.ts";

import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../server/refusal.ts";

/**
 * A `beforeHandle` hook that refuses callers outside `options`: Problem
 * Details, or a redirect to `signIn` or `mfa`.
 *
 * ```ts
 * app.get('/admin', handler, { beforeHandle: guard(bridge, { roles: ['admin'] }) })
 * ```
 */
export function guard<Entries extends readonly AnyEntry[]>(
  bridge: ElysiaBridge<Entries>,
  options: RouteGuardOptions = {},
): (context: { readonly request: Request }) => Promise<Response | undefined> {
  return ({ request }) => {
    const locals = guardedLocals(bridge.context(request));
    return routeRefusal(locals, request, options);
  };
}

/**
 * An `onError` hook that answers thrown `DbException`s (from `.orThrow()`)
 * with Problem Details and leaves every other error to Elysia.
 *
 * ```ts
 * new Elysia().onError(problemOnError())
 * ```
 */
export function problemOnError(
  options: { readonly expose?: boolean } = {},
): (context: {
  readonly error: unknown;
  readonly request: Request;
}) => Response | undefined {
  return ({ error, request }) => errorResponse(error, request, options);
}
