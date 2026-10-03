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
   * `DbError`, become `ORPCError`s. With `refresh`, pair it with
   * `ctx.bs.resolution.apply` in the handler adapter.
   */
  middleware(options?: MiddlewareOptions): OrpcMiddleware<M, F, E, C, P>;
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

    async unwrap(value: unknown): Promise<never> {
      const settled = await settle(() => value);
      if (!settled.ok) throw toOrpcError(settled.error);
      // SAFETY: unwrap returns the settled data, and callers type it through
      // the procedure output.
      return settled.data as never;
    },
  });
}
