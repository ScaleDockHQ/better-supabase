import type { H3Event } from "../bridges/h3.ts";
import type { RouteGuardOptions } from "../server/refusal.ts";

import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../server/refusal.ts";

/**
 * Route middleware that refuses callers outside `options`: Problem Details,
 * or a redirect to `signIn` or `mfa`. Runs after `toH3(...)`.
 *
 * ```ts
 * app.get('/admin', handler, { middleware: [guard({ roles: ['admin'] })] })
 * ```
 */
export function guard(
  options: RouteGuardOptions = {},
): (event: H3Event<object>, next: () => unknown) => Promise<unknown> {
  return async (event, next) => {
    const refused = await routeRefusal(
      guardedLocals(event.context),
      event.req,
      options,
    );
    return refused ?? next();
  };
}

/**
 * An `onError` handler for `new H3({ onError })` that answers thrown
 * `DbException`s (from `.orThrow()`) with Problem Details and leaves every
 * other error to H3.
 */
export function problemOnError(
  options: { readonly expose?: boolean } = {},
): (error: unknown, event: H3Event<object>) => Response | undefined {
  return (error, event) => errorResponse(error, event.req, options);
}
