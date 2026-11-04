import type { AuthSession } from "../auth/view.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { ServerContext } from "../server/server-types.ts";
import type { BetterNext, ContextualNext } from "./types.ts";

import { withExtra } from "../server/extra.ts";

/**
 * Builds `bsb.withContext(factory)`: the factory runs once per base context
 * (one per request and tenant), so `cached()`, `getAccess()` and `action()`
 * share the app's context instead of each rebuilding it.
 */
export function withContextFactory<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  Ref,
  B,
  V extends AuthzVersionCache,
  D,
  X extends object,
>(
  next: BetterNext<M, F, E, C, P, Ref, B, V, D>,
  factory: (
    session: AuthSession<C, P>,
    base: ServerContext<M, F, E, C, P, B, D>,
  ) => X,
  sessionOf: (ctx: ServerContext<M, F, E, C, P, B, D>) => AuthSession<C, P>,
): ContextualNext<M, F, E, C, P, Ref, B, D, X> {
  const built = new WeakMap<object, X>();

  const extraOf = (
    ctx: ServerContext<M, F, E, C, P, B, D>,
    session: AuthSession<C, P> = sessionOf(ctx),
  ): X => {
    const known = built.get(ctx);

    if (known) {
      return known;
    }

    const made = factory(session, ctx);
    built.set(ctx, made);

    return made;
  };

  return {
    cached: async (options) => {
      const ctx = await next.cached(options);

      return withExtra(ctx, extraOf(ctx, ctx.session));
    },
    getAccess: async (source, options) => {
      const access = await next.getAccess(source, options);

      return {
        ...access,
        context: withExtra(
          access.context,
          extraOf(access.context, access.session),
        ),
      };
    },
    action: (options, fn) =>
      next.action(options, (input, ctx, bound) =>
        fn(input, withExtra(ctx, extraOf(ctx)), bound),
      ),
  };
}
