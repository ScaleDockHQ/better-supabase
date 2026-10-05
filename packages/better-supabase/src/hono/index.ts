import type { Context, ErrorHandler, MiddlewareHandler } from "hono";

import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";

import type { AuthState } from "../auth/resolve.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server.ts";

import { dbError, dbErrorOf } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import {
  defineResource,
  type ResourceRouteOptions,
} from "../server/resource.ts";
import {
  defaultExpose,
  guard,
  type MiddlewareOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
export type { ResourceRouteOptions } from "../server/resource.ts";

/** Hono `Env` with the request's better-supabase context in `c.var`. */
export interface HonoEnv<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  Variables: {
    readonly bs: ServerContext<M, F, E, C, P>;
    readonly db: ServerContext<M, F, E, C, P>["db"];
    readonly auth: AuthState<C, P>;
  };
}

export interface HonoOptions extends ServerOptions {
  /** Include error details in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
}

export interface BetterHono<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * The app's Hono `Env`, for `new Hono<typeof bs.Env>()` and
   * `Context<typeof bs.Env>`. Type only: `undefined` at runtime.
   */
  readonly Env: HonoEnv<M, F, E, C, P>;
  /** `new Hono<typeof bs.Env>()` with `onError(bs.onError)` installed. */
  app(): Hono<HonoEnv<M, F, E, C, P>>;
  /** Resolves the caller, enforces `allow` and sets `c.var.bs`, `c.var.db`, `c.var.auth`. */
  middleware(
    options?: MiddlewareOptions,
  ): MiddlewareHandler<HonoEnv<M, F, E, C, P>>;
  /** Wraps a handler: `Result`s become JSON or Problem Details, `undefined` becomes 204. */
  handler(
    fn: (
      c: Context<HonoEnv<M, F, E, C, P>>,
      ctx: ServerContext<M, F, E, C, P>,
    ) => unknown,
    options?: { readonly status?: number },
  ): (c: Context<HonoEnv<M, F, E, C, P>>) => Promise<Response>;
  /**
   * `app.onError(bs.onError)`: `DbException`s (and errors caused by a `DbError`)
   * become Problem Details, Hono's `HTTPException`s keep their own response,
   * and anything else is a 500.
   */
  readonly onError: ErrorHandler<HonoEnv<M, F, E, C, P>>;
  /**
   * REST routes for a table matching `createOpenApi`. Mount with
   * `app.route('/customers', bs.resource('customers'))` behind `middleware()`.
   */
  resource<T extends TableKey<M>>(
    table: T,
    options?: ResourceRouteOptions<M, T>,
  ): Hono<HonoEnv<M, F, E, C, P>>;
}

function contextOf<M extends AnyModels, F extends AnyFunctions, E, C, P>(
  c: Context<HonoEnv<M, F, E, C, P>>,
): ServerContext<M, F, E, C, P> {
  // SAFETY: the middleware stores the ServerContext for this app's generics under "bs".
  const ctx = c.get("bs") as ServerContext<M, F, E, C, P> | undefined;
  if (!ctx) {
    throw new TypeError(
      "better-supabase: no context on this request; add app.use(bs.middleware()) first",
    );
  }
  return ctx;
}

/** Hono integration: a server plus middleware, handlers and REST resources. */
export function createHono<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: HonoOptions = {},
): BetterHono<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();

  const onError: ErrorHandler<HonoEnv<M, F, E, C, P>> = (cause, c) => {
    if (cause instanceof HTTPException) return cause.getResponse();
    const instance = new URL(c.req.url).pathname;
    const thrown = dbErrorOf(cause);
    if (thrown) return problemResponse(thrown, { instance, expose });
    const error = dbError(
      "unexpected",
      expose ? cause.message : "Internal server error",
      { status: 500 },
    );
    return problemResponse(error, { instance, expose });
  };

  return extendServer<BetterHono<M, F, E, C, P>>(server, {
    // SAFETY: `Env` only carries a type, like Drizzle's `$inferSelect`; reading
    // it at runtime is documented as `undefined`.
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- a type-only marker has no runtime value to narrow.
    Env: undefined as unknown as HonoEnv<M, F, E, C, P>,
    onError,

    app() {
      return new Hono<HonoEnv<M, F, E, C, P>>().onError(onError);
    },

    middleware(middlewareOptions = {}) {
      return async (c, next) => {
        const ctx = await server.context(c.req.raw, {
          refresh: middlewareOptions.refresh ?? false,
        });
        const denied = guard(
          ctx.auth,
          middlewareOptions.allow,
          middlewareOptions.aal,
          middlewareOptions.scopes,
        );
        if (denied) {
          return ctx.resolution.apply(
            problemResponse(denied, {
              instance: new URL(c.req.url).pathname,
              expose,
            }),
          );
        }
        c.set("bs", ctx);
        c.set("db", ctx.db);
        c.set("auth", ctx.auth);
        await next();
        c.res = ctx.apply(c.res);
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
      const resource = defineResource(betterSupabase, table, resourceOptions);
      const app = new Hono<HonoEnv<M, F, E, C, P>>();
      const serve =
        (item: boolean) =>
        (c: Context<HonoEnv<M, F, E, C, P>>): Promise<Response> =>
          resource.handle(
            c.req.raw,
            contextOf(c).db,
            item ? c.req.param("id") : undefined,
            { instance: new URL(c.req.url).pathname, expose },
          );
      app.all("/", serve(false));
      if (resource.keyParam) app.all("/:id", serve(true));
      return app;
    },
  });
}
