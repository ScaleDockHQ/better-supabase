import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { ServerContext } from "../server.ts";
import type { ActiveSupport } from "../support.ts";

import { callOf, type ServerCore } from "./core.ts";

/** The keys `withServerContext` reads. */
export interface ServerContextIn<C, P> {
  readonly session: AuthResolution<C, P>;
  readonly tenant: string | undefined;
  readonly support: ActiveSupport | undefined;
}

/**
 * Entry contributing `ctx.bs`, the request's `ServerContext`: `auth`, `db`,
 * `sql`, `supabase`, `replica`, `stats()` and the rest, each built on first
 * read. In a support session `auth`, `db` and `sql` are the target's.
 */
export function withServerContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
): SingleKeyEntry<"bs", ServerContextIn<C, P>, ServerContext<M, F, E, C, P>> {
  return defineMiddleware<
    "bs",
    undefined,
    ServerContextIn<C, P>,
    ServerContext<M, F, E, C, P>
  >({
    key: "bs",
    run: () => (request, ctx) => {
      const call = callOf(ctx);
      const options = call?.options ?? {};
      const bs = core.context(
        ctx.session,
        request,
        ctx.support ? { ...options, support: ctx.support } : options,
        ctx.tenant,
      );
      return Promise.resolve({ bs });
    },
  })();
}
