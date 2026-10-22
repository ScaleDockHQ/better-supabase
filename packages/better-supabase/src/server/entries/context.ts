import type { SingleKeyEntry } from "@supabase/middleware";

import { defineMiddleware } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { ServerContext } from "../server-types.ts";
import type { ActiveSupport } from "../support.ts";
import type { ServerCore } from "./core.ts";

import { callOf } from "./core.ts";

/** The keys `withServerContext` reads. */
export interface ServerContextIn<C, P> {
  readonly session: AuthResolution<C, P>;
  readonly tenant: string | undefined;
  readonly support: ActiveSupport | undefined;
}

/**
 * Entry contributing `ctx.bsb`, the request's `ServerContext`: `auth`, `db`,
 * `sql`, `supabase`, `replica`, `stats()` and the rest, each built on first
 * read. In a support session `auth`, `db` and `sql` are the target's.
 */
export function withServerContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
>(
  core: ServerCore<M, F, E, C, P, B>,
): SingleKeyEntry<
  "bsb",
  ServerContextIn<C, P>,
  ServerContext<M, F, E, C, P, B>
> {
  return defineMiddleware<
    "bsb",
    undefined,
    ServerContextIn<C, P>,
    ServerContext<M, F, E, C, P, B>
  >({
    key: "bsb",
    run: () => (request, ctx) => {
      const call = callOf(ctx);
      const options = call?.options ?? {};

      const bsb = core.context(
        ctx.session,
        request,
        ctx.support ? { ...options, support: ctx.support } : options,
        ctx.tenant,
      );

      return Promise.resolve({ bsb });
    },
  })();
}
