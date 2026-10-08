import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer } from "../server/server.ts";

import { beforeRoute } from "../bridges/before-route.ts";
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

export type { RefusalRedirects } from "../server/refusal.ts";
export type { ActionResult } from "../server/kit.ts";

/** The part of a SolidStart `FetchEvent` the integration reads and writes. */
export interface SolidFetchEvent {
  readonly request: Request;
  readonly response: { readonly headers: Headers };
  readonly locals: Record<string, unknown>;
  /** The H3 event; Nitro's Cloudflare presets put the bindings on its context. */
  readonly nativeEvent?:
    | {
        readonly context?:
          | { readonly cloudflare?: { readonly env?: unknown } | undefined }
          | undefined;
      }
    | undefined;
}

export interface SolidStartOptions extends FrameworkOptions {
  /**
   * `getRequestEvent` from `solid-js/web`, which `require` and `action`
   * call inside `"use server"` functions.
   */
  readonly getRequestEvent: () => SolidFetchEvent | undefined;
  /** The host's env object for `getEnv`; defaults to the Cloudflare bindings. */
  readonly platformEnv?: (event: SolidFetchEvent) => unknown;
}

/** What `createMiddleware` from `@solidjs/start/middleware` takes. */
export interface SolidStartMiddleware {
  readonly onRequest: (event: SolidFetchEvent) => Promise<Response | undefined>;
  readonly onBeforeResponse: (event: SolidFetchEvent) => void;
}

export interface BetterSolidStart<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * Verifies the caller, refreshes the session cookie on navigations and
   * form posts, and puts `db`, `bs`, `auth`, `tenant` and `session` on
   * `event.locals`.
   *
   * ```ts title="src/middleware.ts"
   * export default createMiddleware(bs.middleware)
   * ```
   */
  readonly middleware: SolidStartMiddleware;
  /** The current request's `locals`, inside a `"use server"` function. */
  readonly locals: () => FrameworkLocals<M, F, E, C, P>;
  /**
   * The caller inside a `"use server"` function (a `query`, an `action`,
   * an API route), or a thrown refusal: a redirect to `signIn` or `mfa`
   * when configured, else Problem Details.
   *
   * ```ts
   * const notes = query(async () => {
   *   "use server";
   *   const { db } = await bs.require();
   *   return db.notes.findMany().orThrow();
   * }, "notes");
   * ```
   */
  require<R extends boolean = false>(
    options?: KitRequireOptions<C, P, R>,
  ): Promise<FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>>;
  /**
   * A server function returning an `ActionResult`, for `action()` from
   * `@solidjs/router`: `FormData` or a plain object, validated by `input`.
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: KitActionOptions<S, C, P, R>,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>,
    ) => T,
  ): (input: unknown) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
}

/** SolidStart integration: middleware, guards and server function actions. */
export function createSolidStart<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: SolidStartOptions,
): BetterSolidStart<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const run = beforeRoute([frameworkEntry(server, options, expose)]);
  type Locals = FrameworkLocals<M, F, E, C, P>;

  const eventOf = (): SolidFetchEvent => {
    const event = options.getRequestEvent();
    if (event === undefined || !("bs" in event.locals)) {
      throw new TypeError(
        'better-supabase: no request context; add createMiddleware(bs.middleware) in src/middleware.ts and call this inside a "use server" function',
      );
    }
    return event;
  };
  const scopeOf = (event: SolidFetchEvent): Locals => {
    const locals: object = event.locals;
    // SAFETY: onRequest put localsOf(contributions) on event.locals.
    return locals as Locals;
  };

  return extendServer<BetterSolidStart<M, F, E, C, P>>(server, {
    middleware: {
      onRequest: async (event) => {
        const env = options.platformEnv
          ? options.platformEnv(event)
          : event.nativeEvent?.context?.cloudflare?.env;
        const outcome = await run(event.request, env);
        if (!outcome.reached) return outcome.response;
        for (const cookie of outcome.headers.getSetCookie())
          event.response.headers.append("set-cookie", cookie);
        for (const [name, value] of outcome.headers) {
          if (name !== "set-cookie") event.response.headers.set(name, value);
        }
        Object.assign(
          event.locals,
          localsOf<M, F, E, C, P>(outcome.contributions),
        );
        return;
      },
      onBeforeResponse: () => {
        flushEvents(server, options.waitUntil);
      },
    },

    locals: () => scopeOf(eventOf()),

    require: async (requireOptions = {}) => {
      const event = eventOf();
      const scope = scopeOf(event);
      const caller = await requireCaller(
        scope.bs.auth,
        requireOptions,
        scope.tenant,
      );
      if ("kind" in caller) {
        // oxlint-disable-next-line typescript/only-throw-error -- SolidStart sends a thrown Response from a server function as the answer.
        throw refusalResponse(caller, event.request, options, expose);
      }
      // SAFETY: requireTenant refused a missing tenant.
      return { ...scope, ...caller } as never;
    },

    action(actionOptions, fn) {
      return async (input) => {
        const scope = scopeOf(eventOf());
        const result = await runAction(
          scope.bs.auth,
          actionOptions,
          input,
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
