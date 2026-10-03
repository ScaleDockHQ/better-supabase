import {
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

import { type DbError, dbErrorOf } from "../core/errors.ts";
import { type ProblemDetails, toProblem } from "../core/problem.ts";
import {
  defaultExpose,
  guard,
  type MiddlewareOptions,
  settle,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

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
  middleware(options?: MiddlewareOptions): OrpcMiddleware<M, F, E, C, P>;
  /**
   * A fetch handler for an oRPC handler: passes `{ request }` as the initial
   * context, answers 404 when no procedure matched, and applies the cookies
   * of the request's context (`ctx.apply`).
   */
  fetchHandler(
    handler: OrpcFetchHandler,
    options?: OrpcFetchOptions,
  ): (request: Request) => Promise<Response>;
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
  const contexts = new WeakMap<Request, ServerContext<M, F, E, C, P>>();

  const toOrpcError = (error: DbError): ORPCError<string, ProblemDetails> => {
    const problem = toProblem(error, { expose });
    return new ORPCError(orpcCode(error), {
      message: problem.detail ?? problem.title,
      data: problem,
    });
  };

  return extendServer<BetterOrpc<M, F, E, C, P>>(server, {
    toOrpcError,

    middleware(middlewareOptions = {}) {
      return os
        .$context<OrpcRequestContext>()
        .middleware(async ({ context, next }) => {
          const ctx = await server.context(context.request, {
            refresh: middlewareOptions.refresh ?? false,
          });
          const denied = guard(
            ctx.auth,
            middlewareOptions.allow,
            middlewareOptions.aal,
            middlewareOptions.scopes,
          );
          if (denied) throw toOrpcError(denied);
          contexts.set(context.request, ctx);
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
    },

    fetchHandler(handler, fetchOptions = {}) {
      return async (request) => {
        const { response } = await handler.handle(request, {
          ...(fetchOptions.prefix ? { prefix: fetchOptions.prefix } : {}),
          context: { request },
        });
        const ctx = contexts.get(request);
        const answer = response ?? new Response("Not found", { status: 404 });
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
