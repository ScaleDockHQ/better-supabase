import type { AuthState } from "../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer, ContextOptions, ServerContext } from "./server.ts";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import {
  defaultExpose,
  guard,
  type MiddlewareOptions,
  respond,
} from "./respond.ts";

export interface HandleOptions extends MiddlewareOptions {
  /** Include error messages in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly expose?: boolean;
  /** Problem Details `instance`. Defaults to the request path. */
  readonly instance?: string;
  /** Status for data responses. Defaults to 200 (204 without data). */
  readonly status?: number;
  /**
   * Keeps the invocation alive for event sink sends the handler started:
   * `EdgeRuntime.waitUntil`, the Workers `ctx.waitUntil` or Next's `after`.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
  /** Passed to `server.context()`, e.g. a request-wide stats recorder. */
  readonly context?: Omit<ContextOptions, "refresh">;
  /**
   * Sees every error the handler throws before it becomes a 500, so
   * framework control flow (Next's `redirect()`) can be thrown again.
   */
  readonly rethrow?: (cause: unknown) => void;
}

/** Hands event sink sends still running to `waitUntil`; a no-op without either. */
export function flushEvents(
  server: Pick<BetterServer<AnyModels, AnyFunctions, unknown>, "events">,
  waitUntil: ((promise: Promise<unknown>) => void) | undefined,
): void {
  if (waitUntil && server.events.pending) waitUntil(server.events.settled());
}

/** The 500 for an error a handler threw; the message only when `expose` is set. */
export function unexpectedResponse(
  cause: unknown,
  options: { readonly instance?: string; readonly expose: boolean },
): Response {
  return problemResponse(
    dbError(
      "unexpected",
      options.expose && cause instanceof Error
        ? cause.message
        : "Internal server error",
    ),
    options,
  );
}

/**
 * Runs `run` as the request's caller, the way every built-in adapter does:
 * resolves the context, applies the guard (401/403 Problem Details), turns
 * the return value into a response with `respond()`, turns other thrown
 * errors into a 500, adds the context's cookies with `ctx.apply()` and
 * hands pending event sink sends to `waitUntil`.
 *
 * ```ts
 * export default { fetch: (request, env, ctx) =>
 *   handle(server, request, (c) => c.db.notes.findMany(), { waitUntil: (p) => ctx.waitUntil(p) }) }
 * ```
 */
export async function handle<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  server: BetterServer<M, F, E, C, P>,
  request: Request,
  run: (ctx: ServerContext<M, F, E, C, P>) => unknown,
  options: HandleOptions = {},
): Promise<Response> {
  const expose = options.expose ?? defaultExpose();
  const instance = options.instance ?? new URL(request.url).pathname;
  const ctx = await server.context(request, {
    ...options.context,
    refresh: options.refresh ?? false,
  });
  const denied = guard(ctx.auth, options.allow, options.aal, options.scopes);
  let response: Response;
  try {
    response = denied
      ? problemResponse(denied, { instance, expose })
      : await respond(() => run(ctx), {
          instance,
          expose,
          ...(options.status === undefined ? {} : { status: options.status }),
        });
  } catch (cause) {
    options.rethrow?.(cause);
    response = unexpectedResponse(cause, { instance, expose });
  }
  response = ctx.apply(response);
  flushEvents(server, options.waitUntil);
  return response;
}

/** A request carrying only `token` as a bearer, for resolvers that read headers. */
export function bearerRequest(token: string | null | undefined): Request {
  return new Request("http://localhost/", {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
}

/**
 * Verifies a bare access token (an MCP transport's, a WebSocket's) without
 * cookies or a refresh. An empty token resolves to `anon`.
 */
export async function resolveToken<C, P>(
  server: Pick<BetterServer<AnyModels, AnyFunctions, unknown, C, P>, "resolve">,
  token: string | null | undefined,
): Promise<AuthState<C, P>> {
  const { auth } = await server.resolve(bearerRequest(token), {
    cookies: false,
  });
  return auth;
}
