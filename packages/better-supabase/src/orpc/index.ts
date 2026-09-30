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
  type GuardOptions,
  settle,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions } from "../server/respond.ts";

/** Initial context: pass `{ context: { request } }` to the oRPC handler. */
export interface OrpcRequestContext {
  readonly request: Request;
}

/** What `middleware()` adds to `context`. */
export interface OrpcContext<M extends AnyModels, F extends AnyFunctions, E> {
  readonly bs: ServerContext<M, F, E>;
  readonly db: ServerContext<M, F, E>["db"];
  readonly auth: AuthState;
}

export interface OrpcOptions extends ServerOptions {
  /** Include internal error messages. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
}

export interface MiddlewareOptions extends GuardOptions {
  /** Refresh an expired cookie session. Pair with `ctx.bs.resolution.apply` in the handler adapter. */
  readonly refresh?: boolean;
}

export type OrpcMiddleware<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
> = DecoratedMiddleware<
  OrpcRequestContext,
  OrpcContext<M, F, E>,
  unknown,
  unknown,
  Record<never, never>
>;

export interface BetterOrpc<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
> extends BetterServer<M, F, E> {
  /**
   * Resolves the caller, enforces `allow` and adds `context.db`, `context.auth`
   * and `context.bs`. Thrown `DbException`s, and errors caused by a
   * `DbError`, become `ORPCError`s.
   */
  middleware(options?: MiddlewareOptions): OrpcMiddleware<M, F, E>;
  /** A `Result` (or `AsyncResult`) as data, throwing an `ORPCError` on failure. */
  unwrap<T>(value: Result<T> | PromiseLike<Result<T>>): Promise<T>;
  /** Plain values pass through; thrown `DbException`s become `ORPCError`s. */
  unwrap<T>(value: T | PromiseLike<T>): Promise<T>;
  toORPCError(error: DbError): ORPCError<string, ProblemDetails>;
}

const CODES = new Map<number, string>(
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
export function createOrpc<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  options: OrpcOptions = {},
): BetterOrpc<M, F, E> {
  const server = createServer(sb, options);
  const expose = options.exposeErrors ?? defaultExpose();

  const toORPCError = (error: DbError): ORPCError<string, ProblemDetails> => {
    const problem = toProblem(error, { expose });
    return new ORPCError(orpcCode(error), {
      message: problem.detail ?? problem.title,
      data: problem,
    });
  };

  return extendServer<BetterOrpc<M, F, E>>(server, {
    toORPCError,

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
          );
          if (denied) throw toORPCError(denied);
          try {
            return await next({
              context: { bs: ctx, db: ctx.db, auth: ctx.auth },
            });
          } catch (cause) {
            const thrown = dbErrorOf(cause);
            if (thrown) throw toORPCError(thrown);
            throw cause;
          }
        });
    },

    async unwrap(value: unknown): Promise<never> {
      const settled = await settle(() => value);
      if (!settled.ok) throw toORPCError(settled.error);
      return settled.data as never;
    },
  });
}
