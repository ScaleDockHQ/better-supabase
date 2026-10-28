import type {
  BuilderWithMiddlewares,
  DecoratedMiddleware,
  DecoratedProcedure,
  Schema,
} from "@orpc/server";

import { COMMON_ERROR_STATUS_MAP, ORPCError, os } from "@orpc/server";

import type { AuthState } from "../auth/resolve.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { ProblemDetails } from "../core/problem.ts";
import type { Result } from "../core/result.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { AuthorizeOptions, ResourceLoaderContext } from "../server/kit.ts";
import type { RateLimitRouteOptions } from "../server/rate-limit.ts";
import type { MiddlewareOptions } from "../server/respond.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server-types.ts";
import type { Api } from "../spec/api.ts";
import type { ApiRoute, ApiRouter, ApiRouterOptions } from "./router.ts";

import { tenantOf, toSession } from "../auth/view.ts";
import { claimsOf } from "../core/claims.ts";
import { dbErrorOf } from "../core/errors.ts";
import { toProblem } from "../core/problem.ts";
import { flushEvents } from "../server/adapter.ts";
import { authorizeCaller } from "../server/kit.ts";
import { rateLimitGate } from "../server/rate-limit.ts";
import { refreshFor } from "../server/request-kind.ts";
import {
  assertCookieRefresh,
  defaultExpose,
  guard,
  settle,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import { apiProcedures } from "./router.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

export { toOrpc } from "../bridges/orpc.ts";

export type {
  RateLimiter,
  RateLimitRouteOptions,
  RateLimitVerdict,
  RouteRateLimitRule,
} from "../server/rate-limit.ts";

export type { OrpcHandlerLike, ToOrpcOptions } from "../bridges/orpc.ts";

export type { ApiRoute, ApiRouter, ApiRouterOptions } from "./router.ts";

/**
 * Initial context: pass `{ context: { request } }` to the oRPC handler, or `{
 * context: { headers } }` from an adapter that has no `Request` (the Node
 * handler, a WebSocket peer). `url` defaults to `http://localhost/`.
 */
export type OrpcRequestContext =
  | { readonly request: Request }
  | { readonly headers: Headers; readonly url?: string };

/** What `middleware()` adds to `context`. */
export interface OrpcContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  readonly bsb: ServerContext<M, F, E, C, P, B>;
  readonly db: ServerContext<M, F, E, C, P, B>["db"];
  readonly auth: AuthState<C, P>;
}

export interface OrpcOptions extends ServerOptions {
  /** Include internal error messages. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
  /**
   * Keeps the invocation alive for event sink sends a procedure started, e.g.
   * `EdgeRuntime.waitUntil` or Next's `after`. `fetchHandler` calls it.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/**
 * The part of an oRPC fetch handler (`RPCHandler`, `OpenAPIHandler`)
 * `fetchHandler` calls.
 */
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
  B = unknown,
> = DecoratedMiddleware<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P, B>,
  unknown,
  // oxlint-disable-next-line typescript/no-explicit-any -- as oRPC's `middleware()` default; `unknown` is rejected by `.use()` on a contract procedure with a typed output
  any,
  Record<never, never>
>;

/**
 * What a `rateLimit()` key function reads: the procedure's context, its path
 * and the request (built from `context.headers` when the context has none).
 */
export interface OrpcRateLimitInput<TContext extends OrpcRequestContext> {
  readonly context: TContext;
  readonly path: readonly string[];
  readonly request: Request;
}

/** The middleware `rateLimit()` returns; it adds nothing to `context`. */
export type OrpcRateLimitMiddleware<TContext extends OrpcRequestContext> =
  DecoratedMiddleware<
    TContext,
    Record<never, never>,
    unknown,
    // oxlint-disable-next-line typescript/no-explicit-any -- as oRPC's `middleware()` default, like `OrpcMiddleware`
    any,
    Record<never, never>
  >;

/** Guard and authorize options of `middleware()` and `authed()`. */
export interface OrpcGuardOptions<
  C = unknown,
  P = unknown,
  X = ResourceLoaderContext<C, P>,
>
  extends
    MiddlewareOptions,
    AuthorizeOptions<unknown, C, P, boolean, unknown, X> {}

/** `os` with the caller's context: `bsb.authed().handler(({ context }) => ...)`. */
export type OrpcAuthed<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> = BuilderWithMiddlewares<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P, B>,
  Record<never, never>
>;

/** The Workers execution context, typed structurally. */
export interface OrpcExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}

/** One API operation as an oRPC procedure. */
export type ApiProcedure<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
> = DecoratedProcedure<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P, B>,
  Schema<unknown, unknown>,
  Schema<unknown, unknown>,
  Record<never, never>
>;

export interface BetterOrpc<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * Resolves the caller, enforces `allow` and adds `context.db`, `context.auth`
   * and `context.bsb`. Thrown `DbException`s, and errors caused by a `DbError`,
   * become `ORPCError`s. Serve the router with `fetchHandler` so refreshed
   * session cookies and `bsb-primary-until` reach the response.
   */
  middleware(
    options?: OrpcGuardOptions<
      C,
      P,
      ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
    >,
  ): OrpcMiddleware<M, F, E, C, P, B>;
  /**
   * A procedure builder behind `middleware(options)`, so each procedure starts
   * from the caller's context instead of repeating `.use()`:
   *
   * ```ts
   * export const list = bsb
   *   .authed({ requireTenant: true })
   *   .handler(({ context }) => bsb.unwrap(context.db.customers.list()));
   * ```
   */
  authed(
    options?: OrpcGuardOptions<
      C,
      P,
      ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
    >,
  ): OrpcAuthed<M, F, E, C, P, B>;
  /**
   * A fetch handler for an oRPC handler: passes `{ request }` as the initial
   * context, answers 404 when no procedure matched, and applies the cookies of
   * the request's context (`ctx.apply`). On Workers, pending event sends go to
   * the `ctx.waitUntil` of `fetch(request, env, ctx)` when
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
  /**
   * Counts a hit per call with a rate limiter, such as `createRateLimit()`.
   * `fetchHandler` adds the `RateLimit` (and with `rule`, `RateLimit-Policy`)
   * fields to the response; a refused call throws `TOO_MANY_REQUESTS` and the
   * response carries `Retry-After`. Use it after `middleware()` to key on
   * `context.auth`.
   */
  rateLimit<TContext extends OrpcRequestContext = OrpcRequestContext>(
    options: RateLimitRouteOptions<OrpcRateLimitInput<TContext>>,
  ): OrpcRateLimitMiddleware<TContext>;
  /** A `Result` (or `AsyncResult`) as data, throwing an `ORPCError` on failure. */
  unwrap<T>(value: Result<T> | PromiseLike<Result<T>>): Promise<T>;
  /** Plain values pass through; thrown `DbException`s become `ORPCError`s. */
  // oxlint-disable-next-line typescript/unified-signatures -- the first overload infers the value inside a Result
  unwrap<T>(value: T | PromiseLike<T>): Promise<T>;
  toOrpcError(error: DbError): ORPCError<string, ProblemDetails>;
  /**
   * Serves the API model as oRPC procedures behind `middleware()`, one per
   * operation: every table's REST operations and verbs, through
   * `defineResource`, and every block instance's verbs, through its client on
   * `context.db`. A verb that takes more than one argument takes them as a JSON
   * array.
   *
   * ```ts
   * const api = defineApi(betterSupabase, { info, basePath: "/api" });
   * const { procedures } = bsb.router(api, { meta: openapi });
   * export const handler = bsb.fetchHandler(
   *   new OpenAPIHandler(os.router(procedures)),
   * );
   * ```
   */
  router(
    api: Api,
    options?: ApiRouterOptions<
      OrpcGuardOptions<
        C,
        P,
        ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
      >
    >,
  ): ApiRouter<ApiProcedure<M, F, E, C, P, B>>;
}

const CODES = /* @__PURE__ */ new Map<number, string>(
  Object.entries(COMMON_ERROR_STATUS_MAP).map(([code, status]) => [
    status,
    code,
  ]),
);

/** ORPC code for a `DbError`, from its HTTP status. */
export function orpcCode(error: DbError): string {
  return (
    CODES.get(error.status) ??
    (error.status >= 500 ? "INTERNAL_SERVER_ERROR" : "BAD_REQUEST")
  );
}

function withHeaders(
  response: Response,
  headers: Headers | undefined,
): Response {
  if (headers === undefined) {
    return response;
  }

  const copy = new Response(response.body, response);

  for (const [name, value] of headers) {
    copy.headers.set(name, value);
  }

  return copy;
}

const built = new WeakMap<Headers, Request>();

/**
 * A `Request` carrying `headers`, built once per `Headers` object so nested
 * middleware share the per-request cache.
 */
function requestFromHeaders(
  headers: Headers,
  url = "http://localhost/",
): Request {
  const known = built.get(headers);

  if (known) {
    return known;
  }

  const request = new Request(url, { headers });
  built.set(headers, request);

  return request;
}

/** The context's request, built from its headers when it has none. */
function requestOf(context: OrpcRequestContext): Request {
  return "request" in context
    ? context.request
    : requestFromHeaders(context.headers, context.url);
}

/** ORPC integration: middleware adding the caller's repositories to `context`. */
export function createOrpc<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: OrpcOptions = {},
): BetterOrpc<M, F, E, C, P, B> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const tenantClaim = claimsOf(betterSupabase.meta).tenant;

  const contexts = new WeakMap<
    Request,
    { ctx: ServerContext<M, F, E, C, P, B>; refresh: boolean; cookies: boolean }
  >();

  const limits = new WeakMap<Request, Headers>();

  const toOrpcError = (error: DbError): ORPCError<string, ProblemDetails> => {
    const problem = toProblem(error, { expose });

    return new ORPCError(orpcCode(error), {
      message: problem.detail ?? problem.title,
      data: problem,
    });
  };

  const middleware = (
    middlewareOptions: OrpcGuardOptions<
      C,
      P,
      ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
    > = {},
  ): OrpcMiddleware<M, F, E, C, P, B> => {
    assertCookieRefresh(middlewareOptions);

    const cookies = middlewareOptions.cookies;

    return os
      .$context<OrpcRequestContext>()
      .middleware(async ({ context, next }, input: unknown) => {
        const request = requestOf(context);
        // Nested middleware resolves the request once; the context is kept
        // before the guard so a denied call still returns rotated cookies.
        const refresh = refreshFor(middlewareOptions.refresh, request) ?? false;

        const readsCookies = cookies !== false;
        const known = contexts.get(request);

        // A context resolved from the cookie never serves a `cookies: false`
        // middleware, nor the other way round.
        const reuse =
          known?.cookies === readsCookies && (known.refresh || !refresh);

        const ctx = reuse
          ? known.ctx
          : await server.context(request, { refresh, cookies: readsCookies });

        contexts.set(request, {
          ctx,
          refresh: reuse ? known.refresh || refresh : refresh,
          cookies: readsCookies,
        });

        const denied = guard(
          ctx.auth,
          middlewareOptions.allow,
          middlewareOptions.aal,
          middlewareOptions.scopes,
        );

        if (denied) {
          throw toOrpcError(denied);
        }

        const caller = await authorizeCaller(
          ctx.auth,
          middlewareOptions,
          input,
          tenantOf(toSession(ctx.auth), tenantClaim),
          options.authorizer,
          ctx,
        );

        if ("kind" in caller) {
          throw toOrpcError(caller);
        }

        try {
          return await next({
            context: { bsb: ctx, db: ctx.db, auth: ctx.auth },
          });
        } catch (cause) {
          const thrown = dbErrorOf(cause);

          if (thrown) {
            throw toOrpcError(thrown);
          }

          throw cause;
        }
      });
  };

  return extendServer<BetterOrpc<M, F, E, C, P, B>>(server, {
    toOrpcError,

    middleware,

    rateLimit<TContext extends OrpcRequestContext>(
      rateLimitOptions: RateLimitRouteOptions<OrpcRateLimitInput<TContext>>,
    ): OrpcRateLimitMiddleware<TContext> {
      const gate = rateLimitGate(rateLimitOptions);

      return os
        .$context<TContext>()
        .middleware(async ({ context, path, next }) => {
          const request = requestOf(context);
          const outcome = await gate({ context, path, request });

          if (outcome.kind === "skip") {
            return next();
          }

          const kept = limits.get(request) ?? new Headers();

          for (const [name, value] of outcome.headers) {
            kept.set(name, value);
          }

          limits.set(request, kept);

          if (outcome.kind === "deny") {
            throw toOrpcError(outcome.error);
          }

          return next();
        });
    },

    authed(authedOptions) {
      return os.$context<OrpcRequestContext>().use(middleware(authedOptions));
    },

    fetchHandler(handler, fetchOptions = {}) {
      return async (request, _env, executionContext) => {
        try {
          const { response } = await handler.handle(request, {
            ...(fetchOptions.prefix ? { prefix: fetchOptions.prefix } : {}),
            context: { request },
          });

          const ctx = contexts.get(request)?.ctx;

          const answer = withHeaders(
            response ?? new Response("Not found", { status: 404 }),
            limits.get(request),
          );

          return ctx ? ctx.apply(answer) : answer;
        } finally {
          flushEvents(
            server,
            options.waitUntil ??
              (executionContext
                ? (promise) => {
                    executionContext.waitUntil(promise);
                  }
                : undefined),
          );
        }
      };
    },

    async unwrap(value: unknown): Promise<never> {
      const settled = await settle(() => value);

      if (!settled.ok) {
        throw toOrpcError(settled.error);
      }

      // SAFETY: unwrap returns the settled data, and callers type it through
      // the procedure output.
      return settled.data as never;
    },

    router(api, routerOptions = {}) {
      const procedures: Record<string, ApiProcedure<M, F, E, C, P, B>> = {};
      const routes: ApiRoute[] = [];

      for (const { route, run } of apiProcedures(
        betterSupabase,
        options.authorizer,
        api,
        routerOptions.resources,
      )) {
        const base = os
          .$context<OrpcRequestContext>()
          .use(middleware(routerOptions.guard));

        const routed = routerOptions.meta
          ? base.meta(routerOptions.meta(route))
          : base;

        procedures[route.operationId] = routed.handler(
          async ({ input, context }) => {
            const settled = await settle(() =>
              run({ input, db: context.db, request: requestOf(context) }),
            );

            if (!settled.ok) {
              throw toOrpcError(settled.error);
            }

            return settled.data;
          },
        );

        routes.push(route);
      }

      return { procedures, routes };
    },
  });
}
