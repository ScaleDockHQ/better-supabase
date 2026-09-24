import type { Context, ErrorHandler, MiddlewareHandler } from 'hono';

import { Hono } from 'hono';

import type { AuthState } from '../auth/resolve.ts';
import type { BetterSupabase } from '../core/define.ts';
import type { AnyFunctions, AnyModels, TableKey } from '../schema/types.ts';
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from '../server/server.ts';

import { DbException, dbError } from '../core/errors.ts';
import { problemResponse } from '../core/problem.ts';
import {
  defineResource,
  type ResourceRouteOptions,
} from '../server/resource.ts';
import {
  defaultExpose,
  guard,
  type GuardOptions,
  respond,
} from '../server/respond.ts';
import { createServer, extendServer } from '../server/server.ts';

export type { GuardOptions } from '../server/respond.ts';
export type { ResourceRouteOptions } from '../server/resource.ts';

/** Hono `Env` with the request's better-supabase context in `c.var`. */
export interface BetterEnv<M extends AnyModels, F extends AnyFunctions, E> {
  Variables: {
    readonly bs: ServerContext<M, F, E>;
    readonly db: ServerContext<M, F, E>['db'];
    readonly auth: AuthState;
  };
}

export interface HonoOptions extends ServerOptions {
  /** Include error details in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
}

export interface MiddlewareOptions extends GuardOptions {
  /**
   * Refresh an expired cookie session and send the new cookies. Only for
   * routes browsers call with cookies; bearer tokens never refresh.
   */
  readonly refresh?: boolean;
}

export interface BetterHono<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
> extends BetterServer<M, F, E> {
  /** Resolves the caller, enforces `allow` and sets `c.var.bs`, `c.var.db`, `c.var.auth`. */
  middleware(
    options?: MiddlewareOptions,
  ): MiddlewareHandler<BetterEnv<M, F, E>>;
  /** Wraps a handler: `Result`s become JSON or Problem Details, `undefined` becomes 204. */
  handle(
    handler: (
      c: Context<BetterEnv<M, F, E>>,
      ctx: ServerContext<M, F, E>,
    ) => unknown,
    options?: { readonly status?: number },
  ): (c: Context<BetterEnv<M, F, E>>) => Promise<Response>;
  /** `app.onError(bs.onError)`: `DbException`s become Problem Details, others a 500. */
  readonly onError: ErrorHandler<BetterEnv<M, F, E>>;
  /**
   * REST routes for a table matching `createOpenApi`. Mount with
   * `app.route('/customers', bs.resource('customers'))` behind `middleware()`.
   */
  resource<T extends TableKey<M>>(
    table: T,
    options?: ResourceRouteOptions<M, T>,
  ): Hono<BetterEnv<M, F, E>>;
}

function contextOf<M extends AnyModels, F extends AnyFunctions, E>(
  c: Context<BetterEnv<M, F, E>>,
): ServerContext<M, F, E> {
  const ctx = c.get('bs') as ServerContext<M, F, E> | undefined;
  if (!ctx) {
    throw new TypeError(
      'better-supabase: no context on this request; add app.use(bs.middleware()) first',
    );
  }
  return ctx;
}

/** Hono integration: a server plus middleware, handlers and REST resources. */
export function createHono<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  options: HonoOptions = {},
): BetterHono<M, F, E> {
  const server = createServer(sb, options);
  const expose = options.exposeErrors ?? defaultExpose();

  const onError: ErrorHandler<BetterEnv<M, F, E>> = (cause, c) => {
    const instance = new URL(c.req.url).pathname;
    if (cause instanceof DbException) {
      return problemResponse(cause.error, { instance, expose });
    }
    const error = dbError(
      'unexpected',
      expose ? cause.message : 'Internal server error',
      { status: 500 },
    );
    return problemResponse(error, { instance, expose });
  };

  return extendServer<BetterHono<M, F, E>>(server, {
    onError,

    middleware(middlewareOptions = {}) {
      return async (c, next) => {
        const ctx = await server.context(c.req.raw, {
          refresh: middlewareOptions.refresh ?? false,
        });
        const denied = guard(ctx.auth, middlewareOptions.allow);
        if (denied) {
          return ctx.resolution.apply(
            problemResponse(denied, {
              instance: new URL(c.req.url).pathname,
              expose,
            }),
          );
        }
        c.set('bs', ctx);
        c.set('db', ctx.db);
        c.set('auth', ctx.auth);
        await next();
        c.res = ctx.resolution.apply(c.res);
        return undefined;
      };
    },

    handle(handler, handleOptions = {}) {
      return (c) => {
        const ctx = contextOf(c);
        return respond(() => handler(c, ctx), {
          instance: new URL(c.req.url).pathname,
          expose,
          ...handleOptions,
        });
      };
    },

    resource(table, resourceOptions) {
      const resource = defineResource(sb, table, resourceOptions);
      const app = new Hono<BetterEnv<M, F, E>>();
      const serve =
        (item: boolean) =>
        (c: Context<BetterEnv<M, F, E>>): Promise<Response> =>
          resource.handle(
            c.req.raw,
            contextOf(c).db,
            item ? c.req.param('id') : undefined,
            { instance: new URL(c.req.url).pathname, expose },
          );
      app.all('/', serve(false));
      if (resource.keyParam) app.all('/:id', serve(true));
      return app;
    },
  });
}
