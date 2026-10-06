import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthState } from "../../auth/resolve.ts";

import { problemResponse } from "../../core/problem.ts";
import { defaultExpose, guard, type GuardOptions } from "../respond.ts";

export interface GuardEntryConfig extends GuardOptions {
  /** Include error messages in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly expose?: boolean;
}

/**
 * Entry that answers callers `allow`, `aal` or `scopes` refuse with a 401 or
 * 403 Problem Details response, before the handler runs. It contributes
 * `ctx.guard`, the options the caller passed.
 */
export function withGuard<C, P>(
  config: GuardEntryConfig = {},
): SingleKeyEntry<"guard", { readonly auth: AuthState<C, P> }, GuardOptions> {
  const { expose = defaultExpose(), ...options } = config;
  return defineMiddleware<
    "guard",
    undefined,
    { readonly auth: AuthState<C, P> },
    GuardOptions
  >({
    key: "guard",
    run: () => (request, ctx) => {
      const denied = guard(
        ctx.auth,
        options.allow,
        options.aal,
        options.scopes,
      );
      return Promise.resolve(
        denied
          ? problemResponse(denied, {
              instance: new URL(request.url).pathname,
              expose,
            })
          : { guard: options },
      );
    },
  })();
}
