import {
  type BuilderWithMiddlewares,
  COMMON_ERROR_STATUS_MAP,
  type DecoratedMiddleware,
  ORPCError,
  os,
} from "@orpc/server";

import type { AuthState } from "../auth/resolve.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { Result } from "../core/result.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server.ts";

import { tenantOf, toSession } from "../auth/view.ts";
import { claimsOf } from "../core/claims.ts";
import { type DbError, dbErrorOf } from "../core/errors.ts";
import { type ProblemDetails, toProblem } from "../core/problem.ts";
import { flushEvents } from "../server/adapter.ts";
import { authorizeCaller, type KitRequireOptions } from "../server/kit.ts";
import { refreshFor } from "../server/refresh.ts";
import {
  defaultExpose,
  guard,
  type MiddlewareOptions,
  settle,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
export { toOrpc } from "../bridges/orpc.ts";
export type { OrpcHandlerLike, ToOrpcOptions } from "../bridges/orpc.ts";

/** Initial context: pass `{ context: { request } }` to the oRPC handler. */
export interface OrpcRequestContext {
  readonly request: Request;
}

/** What `middleware()` adds to `context`. */
export interface OrpcContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly bs: ServerContext<M, F, E, C, P>;
  readonly db: ServerContext<M, F, E, C, P>["db"];
  readonly auth: AuthState<C, P>;
}

export interface OrpcOptions extends ServerOptions {
  /** Include internal error messages. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
  /**
   * Keeps the invocation alive for event sink sends a procedure started,
   * e.g. `EdgeRuntime.waitUntil` or Next's `after`. `fetchHandler` calls it.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** The part of an oRPC fetch handler (`RPCHandler`, `OpenAPIHandler`) `fetchHandler` calls. */
export interface OrpcFetchHandler {
  handle(
    request: Request,
    options: {
      readonly prefix?: `/${string}`;
      readonly context: OrpcRequestContext;
    },
  ): Promise<{
    readonly matched: boolean;
    readonly response?: Response | undefined;
  }>;
}

export interface OrpcFetchOptions {
  /** Path prefix the router is mounted under, e.g. `/rpc`. */
  readonly prefix?: `/${string}`;
}

export type OrpcMiddleware<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = DecoratedMiddleware<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P>,
  unknown,
  unknown,
  Record<never, never>
>;

/** Guard and authorize options of `middleware()` and `authed()`. */
export interface OrpcGuardOptions<C = unknown, P = unknown>
  extends MiddlewareOptions, KitRequireOptions<C, P> {}

/** `os` with the caller's context: `bs.authed().handler(({ context }) => ...)`. */
export type OrpcAuthed<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = BuilderWithMiddlewares<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P>,
  Record<never, never>
>;

/** The Workers execution context, typed structurally. */
export interface OrpcExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}

export interface BetterOrpc<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * Resolves the caller, enforces `allow` and adds `context.db`, `context.auth`
   * and `context.bs`. Thrown `DbException`s, and errors caused by a
   * `DbError`, become `ORPCError`s. Serve the router with `fetchHandler` so
   * refreshed session cookies and `bs-primary-until` reach the response.
   */
  middleware(options?: OrpcGuardOptions<C, P>): OrpcMiddleware<M, F, E, C, P>;
  /**
   * A procedure builder behind `middleware(options)`, so each procedure
   * starts from the caller's context instead of repeating `.use()`:
   *
   * ```ts
   * export const list = bs.authed({ requireTenant: true })
   *   .handler(({ context }) => bs.unwrap(context.db.customers.findMany()))
   * ```
   */
  authed(options?: OrpcGuardOptions<C, P>): OrpcAuthed<M, F, E, C, P>;
  /**
   * A fetch handler for an oRPC handler: passes `{ request }` as the initial
   * context, answers 404 when no procedure matched, and applies the cookies
   * of the request's context (`ctx.apply`). On Workers, pending event sends
   * go to the `ctx.waitUntil` of `fetch(request, env, ctx)` when
   * `OrpcOptions.waitUntil` is unset.
   */
  fetchHandler(
    handler: OrpcFetchHandler,
    options?: OrpcFetchOptions,
  ): (
    request: Request,
    env?: unknown,
    executionContext?: OrpcExecutionContext,
  ) => Promise<Response>;
  /** A `Result` (or `AsyncResult`) as data, throwing an `ORPCError` on failure. */
  unwrap<T>(value: Result<T> | PromiseLike<Result<T>>): Promise<T>;
  /** Plain values pass through; thrown `DbException`s become `ORPCError`s. */
  unwrap<T>(value: T | PromiseLike<T>): Promise<T>;
  toOrpcError(error: DbError): ORPCError<string, ProblemDetails>;
}

const CODES = /* @__PURE__ */ new Map<number, string>(
  Object.entries(COMMON_ERROR_STATUS_MAP).map(([code, status]) => [
    status,
    code,
  ]),
);

/** oRPC code for a `DbError`, from its HTTP status. */
export function orpcCode(error: DbError): string {
  return (
    CODES.get(error.status) ??
    (error.status >= 500 ? "INTERNAL_SERVER_ERROR" : "BAD_REQUEST")
  );
}

/** oRPC integration: middleware adding the caller's repositories to `context`. */
export function createOrpc<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: OrpcOptions = {},
): BetterOrpc<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const tenantClaim = claimsOf(betterSupabase.meta).tenant;
  const contexts = new WeakMap<
    Request,
    { ctx: ServerContext<M, F, E, C, P>; refresh: boolean }
  >();

  const toOrpcError = (error: DbError): ORPCError<string, ProblemDetails> => {
    const problem = toProblem(error, { expose });
    return new ORPCError(orpcCode(error), {
      message: problem.detail ?? problem.title,
      data: problem,
    });
  };

  const middleware = (
    middlewareOptions: OrpcGuardOptions<C, P> = {},
  ): OrpcMiddleware<M, F, E, C, P> => {
    return os
      .$context<OrpcRequestContext>()
      .middleware(async ({ context, next }) => {
        // Nested middleware resolves the request once; the context is kept
        // before the guard so a denied call still returns rotated cookies.
        const refresh =
          refreshFor(middlewareOptions.refresh, context.request) ?? false;
        const known = contexts.get(context.request);
        const ctx =
          known && (known.refresh || !refresh)
            ? known.ctx
            : await server.context(context.request, { refresh });
        contexts.set(context.request, {
          ctx,
          refresh: refresh || (known?.refresh ?? false),
        });
        const denied = guard(
          ctx.auth,
          middlewareOptions.allow,
          middlewareOptions.aal,
          middlewareOptions.scopes,
        );
        if (denied) throw toOrpcError(denied);
        if (middlewareOptions.requireTenant || middlewareOptions.authorize) {
          const caller = await authorizeCaller(
            ctx.auth,
            middlewareOptions,
            undefined,
            tenantOf(toSession(ctx.auth), tenantClaim),
          );
          if ("kind" in caller) throw toOrpcError(caller);
        }
        try {
          return await next({
            context: { bs: ctx, db: ctx.db, auth: ctx.auth },
          });
        } catch (cause) {
          const thrown = dbErrorOf(cause);
          if (thrown) throw toOrpcError(thrown);
          throw cause;
        }
      });
  };

  return extendServer<BetterOrpc<M, F, E, C, P>>(server, {
    toOrpcError,

    middleware,

    authed(authedOptions) {
      return os.$context<OrpcRequestContext>().use(middleware(authedOptions));
    },

    fetchHandler(handler, fetchOptions = {}) {
      return async (request, _env, executionContext) => {
        const { response } = await handler.handle(request, {
          ...(fetchOptions.prefix ? { prefix: fetchOptions.prefix } : {}),
          context: { request },
        });
        const ctx = contexts.get(request)?.ctx;
        const answer = response ?? new Response("Not found", { status: 404 });
        flushEvents(
          server,
          options.waitUntil ??
            (executionContext
              ? (promise) => {
                  executionContext.waitUntil(promise);
                }
              : undefined),
        );
        return ctx ? ctx.apply(answer) : answer;
      };
    },

    async unwrap(value: unknown): Promise<never> {
      const settled = await settle(() => value);
      if (!settled.ok) throw toOrpcError(settled.error);
      // SAFETY: unwrap returns the settled data, and callers type it through
      // the procedure output.
      return settled.data as never;
    },
  });
}
