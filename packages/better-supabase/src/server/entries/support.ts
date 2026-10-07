import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { ActiveSupport } from "../support.ts";

import { callOf, type ServerCore, supportLookup } from "./core.ts";

/**
 * Entry contributing `ctx.support`: the support session ("view as user") the
 * request's support cookie names, when `ServerOptions.support` is set and
 * the caller is the admin who started it. `undefined` otherwise.
 */
export function withSupport<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
): SingleKeyEntry<
  "support",
  { readonly session: AuthResolution<C, P> },
  ActiveSupport | undefined
> {
  return defineMiddleware<
    "support",
    undefined,
    { readonly session: AuthResolution<C, P> },
    ActiveSupport | undefined
  >({
    key: "support",
    run: () => async (request, ctx) => {
      const support =
        callOf(ctx)?.options.support ??
        (await supportLookup(core, request, ctx.session));
      return { support };
    },
  })();
}
