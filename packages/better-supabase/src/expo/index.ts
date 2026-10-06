import type { ImmutableRequest, MiddlewareFunction } from "expo-server";

import { setResponseHeaders, StatusError } from "expo-server";

import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
  ServerOptions,
} from "../server/server.ts";

import { serializeCookie } from "../auth/session.ts";
import { type ExpoParams, toExpo } from "../bridges/expo.ts";
import { DbException } from "../core/errors.ts";
import { toProblem } from "../core/problem.ts";
import { unexpectedResponse } from "../server/adapter.ts";
import { withBetterSupabase } from "../server/composite.ts";
import {
  defaultExpose,
  guard,
  type GuardOptions,
  type MiddlewareOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

/** A request as Expo Router passes it: `ImmutableRequest` in loaders and middleware, `Request` in API routes. */
export type ExpoRequest = Request | ImmutableRequest;

export { toExpo } from "../bridges/expo.ts";
export type { ExpoParams } from "../bridges/expo.ts";

export interface ExpoOptions extends ServerOptions {
  /** Include error details in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
}

export interface ExpoContextOptions
  extends Omit<ContextOptions, "refresh">, GuardOptions {
  /**
   * Refresh an expired cookie session and write the new cookies with
   * `setResponseHeaders`. Defaults to true; bearer tokens never refresh.
   */
  readonly refresh?: boolean;
}

export interface ExpoMiddlewareOptions extends MiddlewareOptions {
  /**
   * Where a caller `allow` refuses goes, e.g. `/sign-in`. Without it the
   * middleware lets every request through and only refreshes the session.
   */
  readonly redirectTo?: string;
}

export interface BetterExpo<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * The verified caller for a server loader, API route or middleware: a
   * bearer token first, the session cookie second. Refreshed session
   * cookies go out through `setResponseHeaders`. With `allow`, a refused
   * caller throws a `StatusError` (401 or 403) that Expo Router answers.
   */
  request(
    request: ExpoRequest,
    options?: ExpoContextOptions,
  ): Promise<ServerContext<M, F, E, C, P>>;
  /**
   * A server loader (`export const loader = bs.loader(...)`) that runs `fn`
   * as the caller. A `DbException` from `.orThrow()` becomes a `StatusError`
   * with the error's status. Throws during static rendering, which has no request.
   */
  loader<T>(
    fn: (
      ctx: ServerContext<M, F, E, C, P>,
      params: ExpoParams,
      request: ImmutableRequest,
    ) => Promise<T> | T,
    options?: ExpoContextOptions,
  ): (request: ImmutableRequest | undefined, params: ExpoParams) => Promise<T>;
  /**
   * An API route handler (`export const GET = bs.handler(...)`): `Result`s
   * become JSON or Problem Details, `undefined` becomes 204.
   */
  handler(
    fn: (
      request: Request,
      ctx: ServerContext<M, F, E, C, P>,
      params: ExpoParams,
    ) => unknown,
    options?: MiddlewareOptions,
  ): (request: Request, params?: ExpoParams) => Promise<Response>;
  /**
   * `+middleware.ts`: refreshes an expired cookie session once per request,
   * before loaders run, and redirects refused callers when `redirectTo` is set.
   */
  middleware(options?: ExpoMiddlewareOptions): MiddlewareFunction;
}

/** `ImmutableRequest` has no body and immutable headers; the resolver only reads URL, method and headers. */
function toRequest(request: ExpoRequest): Request {
  if (request instanceof Request) return request;
  return new Request(request.url, {
    method: request.method,
    headers: new Headers(request.headers),
  });
}

/** Sends the cookies and headers `ctx.apply` would add to a response. */
function writeHeaders(
  ctx: Pick<ServerContext<AnyModels, AnyFunctions, unknown>, "cookies"> & {
    readonly resolution: { readonly headers: Readonly<Record<string, string>> };
  },
): void {
  const cookies = ctx.cookies().map(serializeCookie);
  const others = Object.entries(ctx.resolution.headers);
  if (cookies.length === 0 && others.length === 0) return;
  setResponseHeaders((headers) => {
    const sent = new Set(headers.getSetCookie());
    for (const cookie of cookies)
      if (!sent.has(cookie)) headers.append("set-cookie", cookie);
    for (const [name, value] of others) headers.set(name, value);
  });
}

function statusError(error: DbError, expose: boolean): StatusError {
  const problem = toProblem(error, { expose });
  return new StatusError(problem.status, {
    error: problem.title,
    ...problem,
  });
}

/** Expo Router integration: server loaders, API routes and `+middleware.ts`. */
export function createExpo<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: ExpoOptions = {},
): BetterExpo<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();

  const request = async (
    incoming: ExpoRequest,
    contextOptions: ExpoContextOptions = {},
  ): Promise<ServerContext<M, F, E, C, P>> => {
    const { allow, aal, scopes, refresh = true, ...rest } = contextOptions;
    const ctx = await server.context(toRequest(incoming), {
      ...rest,
      refresh,
    });
    writeHeaders(ctx);
    if (allow !== undefined || aal !== undefined || scopes !== undefined) {
      const denied = guard(ctx.auth, allow, aal, scopes);
      if (denied) throw statusError(denied, expose);
    }
    return ctx;
  };

  return extendServer<BetterExpo<M, F, E, C, P>>(server, {
    request,

    loader(fn, loaderOptions) {
      return async (incoming, params) => {
        if (!incoming) {
          throw new StatusError(
            500,
            "better-supabase: bs.loader() needs a request; static rendering has none (use createStaticLoader)",
          );
        }
        const ctx = await request(incoming, loaderOptions);
        try {
          return await fn(ctx, params, incoming);
        } catch (cause) {
          if (cause instanceof DbException)
            throw statusError(cause.error, expose);
          throw cause;
        }
      };
    },

    handler(fn, handlerOptions = {}) {
      return toExpo(
        [withBetterSupabase(server, { ...handlerOptions, expose })],
        async (incoming, ctx, params) => {
          const instance = new URL(incoming.url).pathname;
          try {
            return await respond(() => fn(incoming, ctx.bs, params), {
              instance,
              expose,
            });
          } catch (cause) {
            return unexpectedResponse(cause, { instance, expose });
          }
        },
      );
    },

    middleware(middlewareOptions = {}) {
      const { redirectTo, allow, aal, scopes } = middlewareOptions;
      return async (incoming): Promise<Response | void> => {
        const ctx = await server.context(toRequest(incoming), {
          refresh: middlewareOptions.refresh ?? true,
        });
        const url = new URL(incoming.url);
        const target =
          redirectTo === undefined ? undefined : new URL(redirectTo, url);
        if (
          !target ||
          url.pathname === target.pathname ||
          !guard(ctx.auth, allow, aal, scopes)
        ) {
          writeHeaders(ctx);
          return;
        }
        target.searchParams.set("next", url.pathname + url.search);
        return ctx.apply(
          new Response(null, {
            status: 303,
            headers: { location: target.href },
          }),
        );
      };
    },
  });
}
