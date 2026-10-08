import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer } from "../server/server.ts";

import { around, bufferInPlace } from "../bridges/shared.ts";
import { problemResponse } from "../core/problem.ts";
import { flushEvents } from "../server/adapter.ts";
import {
  actionInput,
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
import { defaultExpose, settle } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

/** React Router's `RouterContextProvider`, typed structurally. */
export interface ReactRouterContextProvider {
  get(key: never): unknown;
  set(key: never, value: never): void;
}

/** The arguments of a loader, action or middleware. */
export interface ReactRouterArgs {
  readonly request: Request;
  readonly context: ReactRouterContextProvider;
  readonly params?: Readonly<Record<string, string | undefined>>;
}

export interface ReactRouterOptions extends FrameworkOptions {
  /** `createContext` from `react-router`; the factory makes its own context key. */
  readonly createContext: () => unknown;
  /**
   * The host's env object for `getEnv`, e.g.
   * `({ context }) => context.get(cloudflareContext).env` on Workers.
   */
  readonly platformEnv?: (args: ReactRouterArgs) => unknown;
}

export interface BetterReactRouter<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /** The context key the middleware sets: `context.get(bs.contextKey)`, or `bs.locals(args)`. */
  readonly contextKey: unknown;
  /**
   * Server middleware for `root.tsx`: verifies the caller, refreshes the
   * session cookie on navigations and form posts, and sets the context.
   */
  readonly middleware: (
    args: ReactRouterArgs,
    next: () => Promise<Response>,
  ) => Promise<Response>;
  /** `db`, `bs`, `auth`, `tenant` and the serializable `session` of the request. */
  locals(args: ReactRouterArgs): FrameworkLocals<M, F, E, C, P>;
  /**
   * A loader that runs the guard first. A refused caller gets a redirect to
   * `signIn` or `mfa` when configured, else a thrown Problem Details
   * response for the `ErrorBoundary`. `Result`s unwrap, and a failed one
   * is thrown the same way.
   */
  loader<A extends ReactRouterArgs, T, R extends boolean = false>(
    options: KitRequireOptions<C, P, R>,
    fn: (
      args: A,
      ctx: FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>,
    ) => T,
  ): (args: A) => Promise<Unwrapped<Awaited<T>>>;
  /** An action returning an `ActionResult`, for `useActionData` or `useAction`. */
  action<
    S extends StandardSchemaV1 | undefined,
    T,
    A extends ReactRouterArgs = ReactRouterArgs,
    R extends boolean = false,
  >(
    options: KitActionOptions<S, C, P, R>,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>,
      args: A,
    ) => T,
  ): (args: A) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
}

/** React Router integration: middleware, guarded loaders and actions. */
export function createReactRouter<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: ReactRouterOptions,
): BetterReactRouter<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const run = around([frameworkEntry(server, options, expose)]);
  const key = options.createContext();
  type Locals = FrameworkLocals<M, F, E, C, P>;

  const locals = (args: ReactRouterArgs): Locals => {
    let value: unknown;
    try {
      // SAFETY: the key is the one this factory created; get only reads it.
      value = args.context.get(key as never);
    } catch {
      value = undefined;
    }
    if (typeof value !== "object" || value === null || !("bs" in value)) {
      throw new TypeError(
        "better-supabase: no context; add bs.middleware to the root route's middleware export",
      );
    }
    // SAFETY: the middleware sets Locals under this key.
    return value as Locals;
  };

  return extendServer<BetterReactRouter<M, F, E, C, P>>(server, {
    contextKey: key,

    middleware(args, next) {
      bufferInPlace(args.request);
      return run(
        args.request,
        options.platformEnv?.(args),
        async (contributions) => {
          // SAFETY: the key is the one this factory created, for Locals.
          args.context.set(key as never, localsOf(contributions) as never);
          const response = await next();
          flushEvents(server, options.waitUntil);
          return response;
        },
      );
    },

    locals,

    loader(loaderOptions, fn) {
      return async (args) => {
        const scope = locals(args);
        const caller = await requireCaller(
          scope.bs.auth,
          loaderOptions,
          scope.tenant,
        );
        if ("kind" in caller) {
          // oxlint-disable-next-line typescript/only-throw-error -- React Router sends a thrown Response as the answer.
          throw refusalResponse(caller, args.request, options, expose);
        }
        // SAFETY: requireTenant refused a missing tenant.
        const ctx = { ...scope, ...caller } as never;
        const settled = await settle(() => fn(args, ctx));
        if (!settled.ok) {
          // oxlint-disable-next-line typescript/only-throw-error -- React Router renders a thrown Response in the ErrorBoundary.
          throw problemResponse(settled.error, {
            instance: new URL(args.request.url).pathname,
            expose,
          });
        }
        // SAFETY: the settled data is what fn returned, unwrapped.
        return settled.data as never;
      };
    },

    action(actionOptions, fn) {
      return async (args) => {
        const scope = locals(args);
        const result = await runAction(
          scope.bs.auth,
          actionOptions,
          await actionInput(args.request),
          scope.tenant,
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema; requireTenant refused a missing tenant.
          (parsed, caller) =>
            fn(parsed as never, { ...scope, ...caller } as never, args),
        );
        // SAFETY: the settled data is what fn returned, unwrapped.
        return result as never;
      };
    },
  });
}
