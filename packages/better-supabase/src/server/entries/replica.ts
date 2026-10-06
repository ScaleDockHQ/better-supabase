import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { ServerContext } from "../server.ts";
import type { ServerCore } from "./core.ts";

import { type ReplicaState, withPrimaryPin } from "../replicas.ts";

/**
 * Entry contributing `ctx.replica`, where `ctx.db` reads go when a read URL
 * is configured (`undefined` without one). On the way out it sets the
 * `bs-primary-until` cookie after a write, so the caller's next reads see it.
 */
export function withReplica<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
): SingleKeyEntry<
  "replica",
  { readonly bs: ServerContext<M, F, E, C, P> },
  ReplicaState | undefined
> {
  return defineMiddleware<
    "replica",
    undefined,
    { readonly bs: ServerContext<M, F, E, C, P> },
    ReplicaState | undefined
  >({
    key: "replica",
    run: () =>
      // The seam needs no await: it only edits the response on the way out.
      // oxlint-disable-next-line typescript/require-await -- an async generator is the response-seam shape `defineMiddleware` takes.
      async function* (_request, ctx) {
        const { replica } = ctx.bs;
        const response = yield { replica };
        return withPrimaryPin(response, ctx.bs.replica, core.pinMs);
      },
  })();
}
