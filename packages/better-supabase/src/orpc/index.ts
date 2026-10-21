import type {
  AnySchema,
  BuilderWithMiddlewares,
  DecoratedMiddleware,
  DecoratedProcedure,
  MetaPlugin,
  Schema,
} from "@orpc/server";
import type { StandardSchemaV1 } from "@standard-schema/spec";

import { COMMON_ERROR_STATUS_MAP, ORPCError, os } from "@orpc/server";

import type { AuthState } from "../auth/resolve.ts";
import type {
  BlockDataOf,
  BlockInputOf,
  BlockMethodName,
} from "../blocks/block-method.ts";
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
import type { RouteSpec } from "../spec/options.ts";

import { tenantOf, toSession } from "../auth/view.ts";
import { callWithInput } from "../blocks/block-method.ts";
import { claimsOf } from "../core/claims.ts";
import { dbErrorOf } from "../core/errors.ts";
import { toProblem } from "../core/problem.ts";
import { flushEvents } from "../server/adapter.ts";
import { authorizeCaller } from "../server/kit.ts";
import { rateLimitGate } from "../server/rate-limit.ts";
import { refreshFor } from "../server/refresh.ts";
import { defaultExpose, guard, settle } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

export { toOrpc } from "../bridges/orpc.ts";

export type {
  RateLimiter,
  RateLimitRouteOptions,
  RateLimitVerdict,
  RouteRateLimitRule,
} from "../server/rate-limit.ts";

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
  B = unknown,
> {
  readonly bs: ServerContext<M, F, E, C, P, B>;
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

/** What a `rateLimit()` key function reads: the procedure's context and path. */
export interface OrpcRateLimitInput<TContext extends OrpcRequestContext> {
  readonly context: TContext;
  readonly path: readonly string[];
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

/** `os` with the caller's context: `bs.authed().handler(({ context }) => ...)`. */
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

/** The HTTP route `blockRouter` gives one block method. */
export interface BlockRoute {
  readonly method: "POST";
  readonly path: `/${string}`;
  readonly operationId: string;
}

/** Options of `blockRouter()`. */
export interface BlockRouterOptions<
  Cl,
  K extends BlockMethodName<Cl>,
  G = OrpcGuardOptions,
> {
  /** The path segment and operation id prefix, such as `invoices`. */
  readonly name: string;
  /** The methods to expose; the client is only built per request. */
  readonly methods: readonly K[];
  /** Input schemas by method, such as the generated block input schemas. */
  readonly schemas?: {
    readonly [Name in K]?: StandardSchemaV1<unknown, BlockInputOf<Cl, Name>>;
  };
  /** Guard and authorize options every procedure runs behind. */
  readonly guard?: G;
  /** Tags for the documented routes. */
  readonly tags?: readonly string[];
  /**
   * Route metadata per procedure, such as `openapi` from `@orpc/openapi`, so
   * `OpenAPIHandler` serves each method at its documented route.
   */
  readonly meta?: (
    route: BlockRoute,
  ) => MetaPlugin<AnySchema, AnySchema, Record<never, never>>;
}

/** One block method as an oRPC procedure, typed by its input and data. */
export type BlockProcedure<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  I,
  O,
> = DecoratedProcedure<
  OrpcRequestContext,
  OrpcContext<M, F, E, C, P, B>,
  Schema<I, I>,
  Schema<O, O>,
  Record<never, never>
>;

/** What `blockRouter()` returns: the procedures and their documented routes. */
export interface BlockRouter<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  Cl,
  K extends BlockMethodName<Cl>,
> {
  /** One procedure per method, to mount in `os.router()`. */
  readonly procedures: {
    readonly [Name in K]: BlockProcedure<
      M,
      F,
      E,
      C,
      P,
      B,
      BlockInputOf<Cl, Name>,
      BlockDataOf<Cl, Name>
    >;
  };
  /** The routes for `buildApiModel({ routes })`, one `POST` per method. */
  readonly routes: readonly RouteSpec[];
}

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
   * and `context.bs`. Thrown `DbException`s, and errors caused by a `DbError`,
   * become `ORPCError`s. Serve the router with `fetchHandler` so refreshed
   * session cookies and `bs-primary-until` reach the response.
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
   * export const list = bs
   *   .authed({ requireTenant: true })
   *   .handler(({ context }) =>
   *     bs.unwrap(context.db.customers.findMany()),
   *   );
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
   * Exposes a block's client methods as procedures behind `middleware()`. A
   * method that takes more than one argument takes them as a tuple:
   *
   * ```ts
   * const invoices = bs.blockRouter(
   *   ({ supabase }) => blocks(supabase).invoices,
   *   {
   *     name: "invoices",
   *     methods: ["create", "issue"],
   *     schemas: invoiceInputSchemas,
   *     meta: openapi,
   *   },
   * );
   * export const router = os.router({ invoices: invoices.procedures });
   * ```
   */
  blockRouter<Cl extends object, const K extends BlockMethodName<Cl>>(
    client: (ctx: ServerContext<M, F, E, C, P, B>) => Cl,
    options: BlockRouterOptions<
      Cl,
      K,
      OrpcGuardOptions<
        C,
        P,
        ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
      >
    >,
  ): BlockRouter<M, F, E, C, P, B, Cl, K>;
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
    { ctx: ServerContext<M, F, E, C, P, B>; refresh: boolean }
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
  ): OrpcMiddleware<M, F, E, C, P, B> =>
    os
      .$context<OrpcRequestContext>()
      .middleware(async ({ context, next }, input: unknown) => {
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
            context: { bs: ctx, db: ctx.db, auth: ctx.auth },
          });
        } catch (cause) {
          const thrown = dbErrorOf(cause);

          if (thrown) {
            throw toOrpcError(thrown);
          }

          throw cause;
        }
      });

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
          const outcome = await gate({ context, path });

          if (outcome.kind === "skip") {
            return next();
          }

          const kept = limits.get(context.request) ?? new Headers();

          for (const [name, value] of outcome.headers) {
            kept.set(name, value);
          }

          limits.set(context.request, kept);

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

    blockRouter(client, routerOptions) {
      const procedures: Record<string, unknown> = {};
      const routes: RouteSpec[] = [];

      const schemas: Readonly<Record<string, StandardSchemaV1 | undefined>> =
        routerOptions.schemas ?? {};

      for (const name of routerOptions.methods) {
        const route: BlockRoute = {
          method: "POST",
          path: `/${routerOptions.name}/${name}`,
          operationId: `${routerOptions.name}.${name}`,
        };

        const schema = schemas[name];

        const base = os
          .$context<OrpcRequestContext>()
          .use(middleware(routerOptions.guard));

        const routed = routerOptions.meta
          ? base.meta(routerOptions.meta(route))
          : base;

        const call = async ({
          input,
          context,
        }: {
          readonly input: unknown;
          readonly context: OrpcContext<M, F, E, C, P, B>;
        }): Promise<unknown> => {
          const settled = await settle(() =>
            callWithInput(client(context.bs), name, input),
          );

          if (!settled.ok) {
            throw toOrpcError(settled.error);
          }

          return settled.data;
        };

        procedures[name] = schema
          ? routed.input(schema).handler(call)
          : routed.handler(call);

        routes.push({
          ...route,
          ...(schema ? { input: schema } : {}),
          ...(routerOptions.tags ? { tags: routerOptions.tags } : {}),
        });
      }

      // SAFETY: each procedure runs the named method with the input its
      // schema (or BlockInputOf) types and returns that method's data.
      return { procedures, routes } as never;
    },
  });
}
