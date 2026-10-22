import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  FrameworkLocals,
  LocalsResource,
  FrameworkOptions,
} from "../server/framework.ts";
import type {
  ActionParsed,
  ActionResult,
  AuthorizedContext,
  BlockActionOptions,
  BlockRequireOptions,
  Unwrapped,
} from "../server/kit.ts";
import type { BetterServer } from "../server/server-types.ts";

import { beforeRoute } from "../bridges/before-route.ts";
import { nitroCloudflareEnv } from "../bridges/shared.ts";
import { flushEvents } from "../server/adapter.ts";
import { frameworkEntry, localsOf } from "../server/framework.ts";
import { requireCaller, runAction } from "../server/kit.ts";
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
  /**
   * The H3 2 event; Nitro 3's Cloudflare preset puts the bindings on its
   * request.
   */
  readonly nativeEvent?: { readonly req: Request } | undefined;
}

export interface SolidStartOptions extends FrameworkOptions {
  /**
   * `getRequestEvent` from `solid-js/web`, which `require` and `action` call
   * inside `"use server"` functions.
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
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * Verifies the caller, refreshes the session cookie on navigations and form
   * posts, and puts `db`, `bsb`, `auth`, `tenant` and `session` on
   * `event.locals`.
   *
   * ```ts
   * // src/middleware.ts
   * export default createMiddleware(bsb.middleware);
   * ```
   */
  readonly middleware: SolidStartMiddleware;
  /** The current request's `locals`, inside a `"use server"` function. */
  readonly locals: () => FrameworkLocals<M, F, E, C, P, B>;
  /**
   * The caller inside a `"use server"` function (a `query`, an `action`, an API
   * route), or a thrown refusal: a redirect to `signIn` or `mfa` when
   * configured, else Problem Details.
   *
   * ```ts
   * const notes = query(async () => {
   *   "use server";
   *   const { db } = await bsb.require();
   *   return db.notes.findMany().orThrow();
   * }, "notes");
   * ```
   */
  require<R extends boolean = false>(
    options?: BlockRequireOptions<
      C,
      P,
      R,
      Ref,
      LocalsResource<M, F, E, C, P, B>
    >,
  ): Promise<FrameworkLocals<M, F, E, C, P, B> & AuthorizedContext<C, P, R>>;
  /**
   * A server function returning an `ActionResult`, for `action()` from
   * `@solidjs/router`: `FormData` or a plain object, validated by `input`.
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: BlockActionOptions<
      S,
      C,
      P,
      R,
      Ref,
      LocalsResource<M, F, E, C, P, B>
    >,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P, B> & AuthorizedContext<C, P, R>,
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
  A extends AnyAuthorizer | undefined = undefined,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: SolidStartOptions & { readonly authorizer?: A },
): BetterSolidStart<M, F, E, C, P, PermissionRef<A>, B> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const run = beforeRoute([frameworkEntry(server, options, expose)]);

  type Locals = FrameworkLocals<M, F, E, C, P, B>;

  const eventOf = (): SolidFetchEvent => {
    const event = options.getRequestEvent();

    if (event === undefined || !("bsb" in event.locals)) {
      throw new TypeError(
        'better-supabase: no request context; add createMiddleware(bsb.middleware) in src/middleware.ts and call this inside a "use server" function',
      );
    }

    return event;
  };

  const scopeOf = (event: SolidFetchEvent): Locals => {
    const locals: object = event.locals;

    // SAFETY: onRequest put localsOf(contributions) on event.locals.
    return locals as Locals;
  };

  return extendServer<BetterSolidStart<M, F, E, C, P, PermissionRef<A>, B>>(
    server,
    {
      middleware: {
        onRequest: async (event) => {
          const env = options.platformEnv
            ? options.platformEnv(event)
            : event.nativeEvent && nitroCloudflareEnv(event.nativeEvent.req);

          const outcome = await run(event.request, env);

          if (!outcome.reached) {
            return outcome.response;
          }

          for (const cookie of outcome.headers.getSetCookie()) {
            event.response.headers.append("set-cookie", cookie);
          }

          for (const [name, value] of outcome.headers) {
            if (name !== "set-cookie") {
              event.response.headers.set(name, value);
            }
          }

          Object.assign(
            event.locals,
            localsOf<M, F, E, C, P, B>(outcome.contributions),
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
          scope.bsb.auth,
          requireOptions,
          scope.tenant,
          options.authorizer,
          scope,
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
            scope.bsb.auth,
            actionOptions,
            input,
            scope.tenant,
            // SAFETY: parsed is the validated input, or the raw input when the
            // action has no schema; requireTenant refused a missing tenant.
            (parsed, caller) =>
              fn(parsed as never, { ...scope, ...caller } as never),
            options.authorizer,
            scope,
          );

          // SAFETY: the settled data is what fn returned, unwrapped.
          return result as never;
        };
      },
    },
  );
}
