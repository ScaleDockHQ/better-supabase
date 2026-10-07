import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

import { callOf, type ServerCore, startSupportLookup } from "./core.ts";

/**
 * Entry contributing `ctx.tenant`: the active tenant from
 * `ServerOptions.tenant` (a URL slug, a header), or `undefined`. It becomes
 * `context.tenant` for the `tenant()` plugin, the `better_supabase.tenant`
 * setting over Postgres and the `x-bs-tenant` header over PostgREST. It
 * starts the support lookup that `withSupport` awaits, so both run at once.
 */
export function withTenant<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
): SingleKeyEntry<
  "tenant",
  { readonly session: AuthResolution<C, P> },
  string | undefined
> {
  return defineMiddleware<
    "tenant",
    undefined,
    { readonly session: AuthResolution<C, P> },
    string | undefined
  >({
    key: "tenant",
    run: () => async (request, ctx) => {
      const options = callOf(ctx)?.options;
      if (options?.support === undefined)
        startSupportLookup(core, request, ctx.session);
      const tenant =
        options?.tenant ?? (await core.tenant(request, ctx.session.auth));
      return { tenant };
    },
  })();
}
