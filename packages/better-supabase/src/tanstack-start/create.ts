import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer } from "../server/server.ts";

import { around } from "../bridges/shared.ts";
import {
  type TanStackStartServerArgs,
  tanStackStartServer,
} from "../bridges/tanstack-start.ts";
import { flushEvents } from "../server/adapter.ts";
import {
  type FrameworkLocals,
  type FrameworkOptions,
  frameworkEntry,
  localsOf,
} from "../server/framework.ts";
import {
  type ActionParsed,
  type ActionResult,
  type AuthorizedContext,
  type KitActionOptions,
  type KitRequireOptions,
  requireCaller,
  runAction,
  type Unwrapped,
} from "../server/kit.ts";
import { refusalResponse } from "../server/refusal.ts";
import { defaultExpose } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export interface TanStackStartOptions extends FrameworkOptions {
  /** The host's env object for `getEnv`, read per request. */
  readonly platformEnv?: (request: Request) => unknown;
}

/** What a server function handler receives. */
export interface TanStackStartHandlerArgs<Data, Context> {
  readonly data: Data;
  readonly context: Context;
}

export interface BetterTanStackStart<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * The `.server()` callback of a request middleware: verifies the caller,
   * refreshes the session cookie on navigations and form posts, and puts
   * `db`, `bs`, `auth`, `tenant` and the serializable `session` on `context`.
   *
   * ```ts title="src/start.ts"
   * const supabase = createMiddleware().server(bs.middleware)
   * export const startInstance = createStart(() => ({ requestMiddleware: [supabase] }))
   * ```
   */
  readonly middleware: <Result extends object>(
    args: TanStackStartServerArgs<FrameworkLocals<M, F, E, C, P>, Result>,
  ) => Promise<Result>;
  /**
   * The caller in a server function or route handler, or a thrown
   * refusal: a redirect to `signIn` or `mfa` when configured, else a
   * Problem Details response, which TanStack Start sends.
   */
  require<R extends boolean = false>(
    context: FrameworkLocals<M, F, E, C, P>,
    options?: KitRequireOptions<C, P, R>,
  ): Promise<FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>>;
  /**
   * A `createServerFn().handler()` returning an `ActionResult`, for
   * `useAction`. Pass the same schema to `.inputValidator()` to type `data`
   * on the client; `input` validates it again on the server.
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: KitActionOptions<S, C, P, R>,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>,
    ) => T,
  ): <Data>(
    args: TanStackStartHandlerArgs<Data, FrameworkLocals<M, F, E, C, P>>,
  ) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
}

/** TanStack Start integration: request middleware, guards and server function actions. */
export function createTanStackStart<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: TanStackStartOptions = {},
): BetterTanStackStart<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const requests = new WeakMap<object, Request>();
  type Locals = FrameworkLocals<M, F, E, C, P>;

  const served = tanStackStartServer(
    around([frameworkEntry(server, options, expose)]),
    options.platformEnv,
    (contributions, request): Locals => {
      const locals = localsOf<M, F, E, C, P>(contributions);
      requests.set(locals, request);
      return locals;
    },
  );

  const scopeOf = (context: Locals): Locals => {
    if (typeof context !== "object" || !("bs" in context)) {
      throw new TypeError(
        "better-supabase: no context; add bs.middleware to the request middleware in src/start.ts",
      );
    }
    return context;
  };

  return extendServer<BetterTanStackStart<M, F, E, C, P>>(server, {
    async middleware(args) {
      try {
        return await served(args);
      } finally {
        flushEvents(server, options.waitUntil);
      }
    },

    require: async (context, requireOptions = {}) => {
      const scope = scopeOf(context);
      const caller = await requireCaller(
        scope.bs.auth,
        requireOptions,
        scope.tenant,
      );
      if ("kind" in caller) {
        const request = requests.get(scope) ?? new Request("http://localhost/");
        // oxlint-disable-next-line typescript/only-throw-error -- TanStack Start sends a thrown Response as the answer.
        throw refusalResponse(caller, request, options, expose);
      }
      // SAFETY: requireTenant refused a missing tenant.
      return { ...scope, ...caller } as never;
    },

    action(actionOptions, fn) {
      return async ({ data, context }) => {
        const scope = scopeOf(context);
        const result = await runAction(
          scope.bs.auth,
          actionOptions,
          data,
          scope.tenant,
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema; requireTenant refused a missing tenant.
          (parsed, caller) =>
            fn(parsed as never, { ...scope, ...caller } as never),
        );
        // SAFETY: the settled data is what fn returned, unwrapped.
        return result as never;
      };
    },
  });
}
