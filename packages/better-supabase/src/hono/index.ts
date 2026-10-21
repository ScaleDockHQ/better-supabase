import type { Context, ErrorHandler, MiddlewareHandler } from "hono";

import { withCors } from "@supabase/middleware/cors";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { routePath } from "hono/route";

import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type { CorsOptions } from "../server/cors.ts";
import type {
  BlockRequireOptions,
  ResourceLoaderContext,
} from "../server/kit.ts";
import type { RateLimitRouteOptions } from "../server/rate-limit.ts";
import type { ResourceRouteOptions } from "../server/resource-types.ts";
import type { MiddlewareOptions } from "../server/respond.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
  SharedServer,
} from "../server/server-types.ts";

import { toSession } from "../auth/view.ts";
import { honoMiddleware } from "../bridges/hono.ts";
import { dbErrorOf } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { flushEvents, unexpectedResponse } from "../server/adapter.ts";
import { withBetterSupabase } from "../server/composite.ts";
import { corsConfig } from "../server/cors.ts";
import { requireCaller } from "../server/kit.ts";
import { rateLimitGate } from "../server/rate-limit.ts";
import { defineResource } from "../server/resource.ts";
import { matchResource } from "../server/resources.ts";
import { defaultExpose, respond } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

export type { BlockRequireOptions } from "../server/kit.ts";

export type {
  RateLimiter,
  RateLimitRouteOptions,
  RateLimitVerdict,
  RouteRateLimitRule,
} from "../server/rate-limit.ts";

export { toHono } from "../bridges/hono.ts";

export type { HonoBridge } from "../bridges/hono.ts";

export type {
  ActionArgs,
  ResourceAction,
  ResourceContext,
  ResourceHooks,
  ResourceRouteOptions,
} from "../server/resource-types.ts";

export { defineAction } from "../server/resource-execute.ts";

/** Hono `Env` with the request's better-supabase context in `c.var`. */
export interface HonoEnv<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  Variables: {
    readonly bs: ServerContext<M, F, E, C, P, B>;
    readonly db: ServerContext<M, F, E, C, P, B>["db"];
    readonly auth: AuthState<C, P>;
    /** The caller as plain data, safe to return in a response. */
    readonly session: AuthSession<C, P>;
    /** The active tenant: `ServerOptions.tenant`, then the tenant claim. */
    readonly tenant: string | undefined;
  };
}

export interface HonoOptions extends ServerOptions {
  /**
   * An existing server, such as the one `createNext` returned, so both
   * frameworks share one `createServer`: the same cookies, clients, credentials
   * and event sinks. The server options are then ignored.
   */
  readonly server?: SharedServer;
  /**
   * Answer preflights and add CORS headers to every route of `app()`. `true`
   * uses Supabase's defaults.
   */
  readonly cors?: boolean | CorsOptions;
  /**
   * Include error details in problem responses. Defaults to `NODE_ENV ===
   * 'development'`.
   */
  readonly exposeErrors?: boolean;
  /**
   * Keeps the invocation alive for event sink sends a handler started. Defaults
   * to `c.executionCtx.waitUntil` when the runtime passes one (Workers).
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

export interface BetterHono<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * The app's Hono `Env`, for `new Hono<typeof bs.Env>()` and `Context<typeof
   * bs.Env>`. Type only: `undefined` at runtime.
   */
  readonly Env: HonoEnv<M, F, E, C, P, B>;
  /** `new Hono<typeof bs.Env>()` with `onError(bs.onError)` installed. */
  app(): Hono<HonoEnv<M, F, E, C, P, B>>;
  /**
   * Resolves the caller, enforces `allow` and sets `c.var.bs`, `c.var.db`,
   * `c.var.auth`.
   */
  middleware(
    options?: MiddlewareOptions,
  ): MiddlewareHandler<HonoEnv<M, F, E, C, P, B>>;
  /**
   * A route guard after `middleware()`: `allow`, `aal`, `scopes`,
   * `requireTenant` and `authorize`. A refused caller gets Problem Details.
   *
   * ```ts
   * app.post(
   *   "/invites",
   *   bs.require({ requireTenant: true, roles: ["admin"] }),
   *   handler,
   * );
   * ```
   */
  require: (
    options?: BlockRequireOptions<
      C,
      P,
      boolean,
      Ref,
      ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
    >,
  ) => MiddlewareHandler<HonoEnv<M, F, E, C, P, B>>;
  /**
   * Counts a hit per request with a rate limiter, such as `createRateLimit()`,
   * and adds the `RateLimit` (and with `rule`, `RateLimit-Policy`) fields. A
   * refused request gets a 429 with `Retry-After`.
   *
   * ```ts
   * app.use(
   *   "/api/*",
   *   bs.rateLimit({
   *     limiter,
   *     scope: "api",
   *     rule: { max: 100, period: "1 minute" },
   *     key: (c) => c.req.header("x-api-key"),
   *   }),
   * );
   * ```
   */
  rateLimit(
    options: RateLimitRouteOptions<Context<HonoEnv<M, F, E, C, P, B>>>,
  ): MiddlewareHandler<HonoEnv<M, F, E, C, P, B>>;
  /**
   * Wraps a handler: `Result`s and `AsyncResult`s become JSON or Problem
   * Details, `undefined` becomes 204.
   */
  handler(
    fn: (
      c: Context<HonoEnv<M, F, E, C, P, B>>,
      ctx: ServerContext<M, F, E, C, P, B>,
    ) => unknown,
    options?: { readonly status?: number },
  ): (c: Context<HonoEnv<M, F, E, C, P, B>>) => Promise<Response>;
  /**
   * `app.onError(bs.onError)`: `DbException`s (and errors caused by a
   * `DbError`) become Problem Details, Hono's `HTTPException`s keep their own
   * response, and anything else is a 500.
   */
  readonly onError: ErrorHandler<HonoEnv<M, F, E, C, P, B>>;
  /**
   * REST routes for a table matching the API model: the collection, the item
   * and each action's path. Mount with `app.route('/customers',
   * bs.resource('customers'))` behind `middleware()`.
   */
  resource<T extends TableKey<M>>(
    table: T,
    options?: ResourceRouteOptions<
      M,
      T,
      Ref,
      ServerContext<M, F, E, C, P, B>["db"]
    >,
  ): Hono<HonoEnv<M, F, E, C, P, B>>;
}

function contextOf<M extends AnyModels, F extends AnyFunctions, E, C, P, B>(
  c: Context<HonoEnv<M, F, E, C, P, B>>,
): ServerContext<M, F, E, C, P, B> {
  // SAFETY: the middleware stores the ServerContext for this app's generics under "bs".
  const ctx = c.get("bs") as ServerContext<M, F, E, C, P, B> | undefined;

  if (!ctx) {
    throw new TypeError(
      "better-supabase: no context on this request; add app.use(bs.middleware()) first",
    );
  }

  return ctx;
}

function segmentsOf(path: string): readonly string[] {
  return path.split("/").filter((segment) => segment !== "");
}

/** Hono integration: a server plus middleware, handlers and REST resources. */
export function createHono<
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
  options: HonoOptions & { readonly authorizer?: A } = {},
): BetterHono<M, F, E, C, P, PermissionRef<A>, B> {
  // SAFETY: a shared server was built from the same BetterSupabase, so its type parameters match.
  const server =
    (options.server as BetterServer<M, F, E, C, P, B> | undefined) ??
    createServer(betterSupabase, options);

  const expose = options.exposeErrors ?? defaultExpose();

  const onError: ErrorHandler<HonoEnv<M, F, E, C, P, B>> = (cause, c) => {
    if (cause instanceof HTTPException) {
      return cause.getResponse();
    }

    const instance = new URL(c.req.url).pathname;
    const thrown = dbErrorOf(cause);

    if (thrown) {
      return problemResponse(thrown, { instance, expose });
    }

    return unexpectedResponse(cause, { instance, expose });
  };

  const cors: CorsOptions | undefined =
    options.cors === true
      ? {}
      : options.cors === false
        ? undefined
        : options.cors;

  const corsMiddleware = cors
    ? honoMiddleware([withCors(corsConfig(cors))])
    : undefined;

  const waitUntilOf = (
    c: Context<HonoEnv<M, F, E, C, P, B>>,
  ): ((promise: Promise<unknown>) => void) | undefined => {
    if (options.waitUntil) {
      return options.waitUntil;
    }

    try {
      const executionContext = c.executionCtx;

      return (promise) => {
        executionContext.waitUntil(promise);
      };
    } catch {
      // Hono throws when the runtime passed no execution context (Node, Bun).
      return undefined;
    }
  };

  return extendServer<BetterHono<M, F, E, C, P, PermissionRef<A>, B>>(server, {
    // SAFETY: `Env` only carries a type, like Drizzle's `$inferSelect`; reading
    // it at runtime is documented as `undefined`.
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- a type-only marker has no runtime value to narrow.
    Env: undefined as unknown as HonoEnv<M, F, E, C, P, B>,
    onError,

    app() {
      const app = new Hono<HonoEnv<M, F, E, C, P, B>>().onError(onError);

      if (corsMiddleware) {
        app.use("*", corsMiddleware);
      }

      return app;
    },

    middleware(middlewareOptions = {}) {
      const run = honoMiddleware(
        [withBetterSupabase(server, { ...middlewareOptions, expose })],
        (c, ctx) => {
          // SAFETY: withBetterSupabase(server) contributes this server's ServerContext as `bs`.
          const bs = (ctx as { readonly bs: ServerContext<M, F, E, C, P, B> })
            .bs;

          // SAFETY: withBetterSupabase contributes the resolved tenant as `tenant`.
          const { tenant } = ctx as { readonly tenant: string | undefined };
          c.set("bs", bs);
          c.set("db", bs.db);
          c.set("auth", bs.auth);
          c.set("session", toSession(bs.auth));
          c.set("tenant", tenant);
        },
      );

      return async (c, next) => {
        try {
          await run(c, next);
        } finally {
          flushEvents(server, waitUntilOf(c));
        }
      };
    },

    require:
      (requireOptions = {}) =>
      async (c, next) => {
        const ctx = contextOf(c);

        const caller = await requireCaller(
          ctx.auth,
          requireOptions,
          c.get("tenant"),
          options.authorizer,
          ctx,
        );

        if ("kind" in caller) {
          return problemResponse(caller, {
            instance: new URL(c.req.url).pathname,
            expose,
          });
        }

        return next();
      },

    rateLimit(rateLimitOptions) {
      const gate = rateLimitGate(rateLimitOptions);

      return async (c, next) => {
        const outcome = await gate(c);

        if (outcome.kind === "deny") {
          return problemResponse(outcome.error, {
            instance: new URL(c.req.url).pathname,
            expose,
            headers: outcome.headers,
            format: rateLimitOptions.problem,
          });
        }

        await next();

        if (outcome.kind === "allow") {
          for (const [name, value] of outcome.headers) {
            c.header(name, value);
          }
        }

        return;
      };
    },

    handler(fn, handlerOptions = {}) {
      return (c) => {
        const ctx = contextOf(c);

        return respond(() => fn(c, ctx), {
          instance: new URL(c.req.url).pathname,
          expose,
          ...handlerOptions,
        });
      };
    },

    resource(table, resourceOptions) {
      const resource = defineResource(
        betterSupabase,
        table,
        resourceOptions,
        options.authorizer,
      );

      const { keyParam } = resource;
      const app = new Hono<HonoEnv<M, F, E, C, P, B>>();

      // Every route matches through `matchResource`, which also picks an
      // action over an id; the routes are listed for `app.routes`.
      const serve =
        (pattern: string) =>
        async (c: Context<HonoEnv<M, F, E, C, P, B>>): Promise<Response> => {
          const { pathname } = new URL(c.req.url);

          const mounted =
            segmentsOf(routePath(c)).length - segmentsOf(pattern).length;

          const route = matchResource(
            resource,
            segmentsOf(pathname).slice(mounted),
            pathname,
          );

          if (route instanceof Response) {
            return route;
          }

          return resource.serve(c.req.raw, contextOf(c).db, route.segments, {
            instance: pathname,
            expose,
          });
        };

      const patterns = [
        "/",
        ...resource.plan.actions.map(
          (action) =>
            `/${action.segments.map((segment) => (segment.startsWith("{") ? `:${keyParam}` : segment)).join("/")}`,
        ),
        ...(keyParam ? [`/:${keyParam}`] : []),
        "/*",
      ];

      for (const pattern of patterns) {
        app.all(pattern, serve(pattern));
      }

      return app;
    },
  });
}
