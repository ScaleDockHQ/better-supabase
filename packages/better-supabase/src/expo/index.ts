import type { ImmutableRequest, MiddlewareFunction } from "expo-server";

import { setResponseHeaders, StatusError } from "expo-server";

import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthSession } from "../auth/view.ts";
import type { ExpoParams } from "../bridges/expo.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  Access,
  AccessForOptions,
  Bootstrap,
  BootstrapCallOptions,
  BootstrapMemo,
  BootstrapRow,
} from "../server/bootstrap.ts";
import type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
  ServerOptions,
} from "../server/server-types.ts";

import { serializeCookie } from "../auth/session.ts";
import { snapshotOf } from "../auth/snapshot.ts";
import { tenantOf, toSession } from "../auth/view.ts";
import { toExpo } from "../bridges/expo.ts";
import { claimsOf } from "../core/claims.ts";
import { DbException } from "../core/db-exception.ts";
import { toProblem } from "../core/problem.ts";
import { unexpectedResponse } from "../server/adapter.ts";
import {
  accessOf,
  bootstrapSchema,
  bootstrapWith,
} from "../server/bootstrap.ts";
import {
  sessionIdTag,
  tableTags,
  userSessionTags,
} from "../server/cache-tags.ts";
import { withBetterSupabase } from "../server/composite.ts";
import { refreshFor } from "../server/request-kind.ts";
import { defaultExpose, guard, respond } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

/**
 * A request as Expo Router passes it: `ImmutableRequest` in loaders and
 * middleware, `Request` in API routes.
 */
export type ExpoRequest = Request | ImmutableRequest;

export { toExpo } from "../bridges/expo.ts";

export type { ExpoParams, ToExpoOptions } from "../bridges/expo.ts";

export type {
  Access,
  AccessForOptions,
  Bootstrap,
} from "../server/bootstrap.ts";

export interface ExpoOptions<
  V extends AuthzVersionCache = AuthzVersionCache,
> extends ServerOptions<V> {
  /**
   * Include error details in problem responses. Defaults to `NODE_ENV ===
   * 'development'`.
   */
  readonly exposeErrors?: boolean;
}

export interface ExpoContextOptions
  extends Omit<ContextOptions, "refresh">, GuardOptions {
  /**
   * Refresh an expired cookie session and write the new cookies with
   * `setResponseHeaders`. Defaults to true; bearer tokens and prefetches never
   * refresh, so parallel prefetches never race on the refresh token. When
   * `bsb.middleware()` already ran for the request, the context reads the
   * session it refreshed and never calls Auth again, whatever this option
   * says.
   */
  readonly refresh?: boolean;
}

export interface ExpoBootstrapOptions extends BootstrapCallOptions {
  /** As `ExpoContextOptions.refresh`. */
  readonly refresh?: boolean;
}

export interface ExpoCachedOptions<T extends string = string> {
  /** Extra tags for the entry, next to the session and table tags. */
  readonly tags?: readonly string[];
  /** The tables the entry reads; each adds its table tags. */
  readonly tables?: readonly T[];
  /** The active tenant, e.g. from the loader's `params`. */
  readonly tenant?: string;
}

/**
 * `bsb.cached()`: the caller's context plus the tags an app-side cache stores
 * the entry under. Purge them when the events hub reports an invalidation.
 */
export interface ExpoCached<Ctx, C = unknown, P = unknown> {
  readonly context: Ctx;
  readonly session: AuthSession<C, P>;
  readonly tenant: string | null;
  readonly tags: readonly string[];
}

export interface ExpoMiddlewareOptions extends MiddlewareOptions {
  /**
   * Where a caller `allow` refuses goes, e.g. `/sign-in`. Without it the
   * middleware lets every request through and only refreshes the session.
   */
  readonly redirectTo?: string;
  /**
   * Paths every caller may open, such as `/` or `/pricing`. An entry matches
   * the path itself and everything under it (`/auth` matches `/auth/callback`).
   * The `redirectTo` path and everything under it are always public, so its
   * callback routes never loop back to it.
   */
  readonly publicPaths?: readonly string[];
}

/** `path` is `prefix` or a path under it. */
function under(path: string, prefix: string): boolean {
  const base = prefix.endsWith("/") ? prefix.slice(0, -1) : prefix;

  return base === ""
    ? path === "/"
    : path === base || path.startsWith(`${base}/`);
}

export interface BetterExpo<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
  V extends AuthzVersionCache = AuthzVersionCache,
> extends BetterServer<M, F, E, C, P, B, V> {
  /**
   * The verified caller for a server loader, API route or middleware: a bearer
   * token first, the session cookie second. Refreshed session cookies go out
   * through `setResponseHeaders`. With `allow`, a refused caller throws a
   * `StatusError` (401 or 403) that Expo Router answers.
   */
  request(
    request: ExpoRequest,
    options?: ExpoContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  /**
   * Runs the `bootstrap_<rpc>` wrapper for a loader's caller: the session flag,
   * the live authorization version and the page's data in one call. The layout
   * and page loaders of one navigation share the call for 10 seconds, keyed on
   * the request, the session and the arguments. A signed-out caller makes no
   * call.
   */
  bootstrap<T = unknown>(
    request: ExpoRequest,
    options: ExpoBootstrapOptions,
  ): Promise<Bootstrap<C, P, T>>;
  /**
   * The caller's tenant, live version and `can(permission)`. Pass the bootstrap
   * result so `can` checks against its live version.
   */
  getAccess(
    source: ExpoRequest | SessionSnapshot<C> | null,
    options?: AccessForOptions<C, P>,
  ): Promise<Access<ServerContext<M, F, E, C, P, B>, C, P>>;
  /**
   * The request's context and the tags an app-side cache should store a
   * loader's result under: the user's session tags, the Auth session's tag and
   * the table tags of `tables`. Calls for the same request share one context.
   */
  cached(
    request: ExpoRequest,
    options?: ExpoCachedOptions<Extract<keyof M, string>>,
  ): Promise<ExpoCached<ServerContext<M, F, E, C, P, B>, C, P>>;
  /**
   * A server loader (`export const loader = bsb.loader(...)`) that runs `fn` as
   * the caller. A `DbException` from `.orThrow()` becomes a `StatusError` with
   * the error's status. Throws during static rendering, which has no request.
   */
  loader<T>(
    fn: (
      ctx: ServerContext<M, F, E, C, P, B>,
      params: ExpoParams,
      request: ImmutableRequest,
    ) => Promise<T> | T,
    options?: ExpoContextOptions,
  ): (request: ImmutableRequest | undefined, params: ExpoParams) => Promise<T>;
  /**
   * An API route handler (`export const GET = bsb.handler(...)`): `Result`s
   * become JSON or Problem Details, `undefined` becomes 204.
   */
  handler(
    fn: (
      request: Request,
      ctx: ServerContext<M, F, E, C, P, B>,
      params: ExpoParams,
    ) => unknown,
    options?: MiddlewareOptions,
  ): (request: Request, params?: ExpoParams) => Promise<Response>;
  /**
   * `+middleware.ts`: refreshes an expired cookie session once per request
   * (never on a prefetch), before loaders run, and redirects refused callers
   * when `redirectTo` is set.
   */
  middleware(options?: ExpoMiddlewareOptions): MiddlewareFunction;
}

/**
 * `ImmutableRequest` has no body and immutable headers; the resolver only reads
 * URL, method and headers.
 */
function toRequest(request: ExpoRequest): Request {
  if (request instanceof Request) {
    return request;
  }

  return new Request(request.url, {
    method: request.method,
    headers: new Headers(request.headers),
  });
}

/**
 * Expo-server wraps the incoming request in a new `ImmutableRequest` for the
 * middleware and for each loader, so a handoff can't key on the object. The old
 * cookie header pins it to one session: another request with the same key
 * carries the same cookies and would refresh to the same session.
 */
const HANDOFF_TTL_MS = 10_000;

interface Handoff {
  /**
   * The cookie header after the middleware's refresh, or undefined when it
   * wrote no cookies.
   */
  readonly cookie: string | undefined;
  readonly expires: number;
}

/** How long the loaders of one navigation share a bootstrap call. */
const BOOTSTRAP_TTL_MS = 10_000;

interface BootEntry {
  readonly call: Promise<BootstrapRow>;
  readonly expires: number;
}

function handoffKey(request: ExpoRequest): string {
  return `${request.method} ${request.url}\n${request.headers.get("cookie") ?? ""}`;
}

/** The request with its cookie header replaced, keeping method and body. */
function withCookie(request: Request, cookie: string | undefined): Request {
  if (cookie === undefined) {
    return request;
  }

  const headers = new Headers(request.headers);
  headers.set("cookie", cookie);

  return new Request(request, { headers });
}

/** Sends the cookies and headers `ctx.apply` would add to a response. */
function writeHeaders(
  ctx: Pick<ServerContext<AnyModels, AnyFunctions, unknown>, "cookies"> & {
    readonly resolution: { readonly headers: Readonly<Record<string, string>> };
  },
): void {
  const cookies = ctx.cookies().map(serializeCookie);
  const others = Object.entries(ctx.resolution.headers);

  if (cookies.length === 0 && others.length === 0) {
    return;
  }

  setResponseHeaders((headers) => {
    const sent = new Set(headers.getSetCookie());

    for (const cookie of cookies) {
      if (!sent.has(cookie)) {
        headers.append("set-cookie", cookie);
      }
    }

    for (const [name, value] of others) {
      headers.set(name, value);
    }
  });
}

function statusError(error: DbError, expose: boolean): StatusError {
  const problem = toProblem(error, { expose });

  return new StatusError(problem.status, { error: problem.title, ...problem });
}

/** Expo Router integration: server loaders, API routes and `+middleware.ts`. */
export function createExpo<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
  V extends AuthzVersionCache = AuthzVersionCache,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: ExpoOptions<V> = {},
): BetterExpo<M, F, E, C, P, B, V> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const handoffs = new Map<string, Handoff>();
  const boots = new Map<string, BootEntry>();

  const contexts = new WeakMap<
    ExpoRequest,
    Map<string, Promise<ServerContext<M, F, E, C, P, B>>>
  >();

  const tenantClaim = claimsOf(betterSupabase.meta).tenant;

  const handOff = (incoming: ExpoRequest, cookie: string | undefined): void => {
    const now = Date.now();

    // Insertion order is expiry order, so the expired entries lead.
    for (const [key, entry] of handoffs) {
      if (entry.expires > now) {
        break;
      }

      handoffs.delete(key);
    }

    handoffs.set(handoffKey(incoming), {
      cookie,
      expires: now + HANDOFF_TTL_MS,
    });
  };

  const handedOff = (incoming: ExpoRequest): Handoff | undefined => {
    const entry = handoffs.get(handoffKey(incoming));

    return entry && entry.expires > Date.now() ? entry : undefined;
  };

  const request = async (
    incoming: ExpoRequest,
    contextOptions: ExpoContextOptions = {},
  ): Promise<ServerContext<M, F, E, C, P, B>> => {
    const { allow, aal, scopes, refresh = true, ...rest } = contextOptions;
    const handoff = handedOff(incoming);

    const resolved = toRequest(incoming);

    const ctx = await server.context(
      handoff ? withCookie(resolved, handoff.cookie) : resolved,
      { ...rest, refresh: !handoff && refresh },
    );

    writeHeaders(ctx);

    if (allow !== undefined || aal !== undefined || scopes !== undefined) {
      const denied = guard(ctx.auth, allow, aal, scopes);

      if (denied) {
        throw statusError(denied, expose);
      }
    }

    return ctx;
  };

  /** The loader's tenant, then `ExpoOptions.tenant`, then the token's claim. */
  const tenantFor = async (
    incoming: ExpoRequest,
    ctx: ServerContext<M, F, E, C, P, B>,
    explicit: string | undefined,
  ): Promise<string | undefined> =>
    explicit ??
    (await options.tenant?.(toRequest(incoming), ctx.auth)) ??
    tenantOf(toSession(ctx.auth), tenantClaim);

  const bootMemo =
    (incoming: ExpoRequest): BootstrapMemo =>
    (key, run) => {
      const now = Date.now();

      // Insertion order is expiry order, so the expired entries lead.
      for (const [stored, entry] of boots) {
        if (entry.expires > now) {
          break;
        }

        boots.delete(stored);
      }

      const full = `${handoffKey(incoming)}\n${key}`;
      const hit = boots.get(full);

      if (hit) {
        return hit.call;
      }

      const call = run();
      boots.set(full, { call, expires: now + BOOTSTRAP_TTL_MS });
      call.catch(() => {
        boots.delete(full);
      });

      return call;
    };

  const contextFor = (
    incoming: ExpoRequest,
    tenant: string | undefined,
  ): Promise<ServerContext<M, F, E, C, P, B>> => {
    let byTenant = contexts.get(incoming);

    if (!byTenant) {
      byTenant = new Map();
      contexts.set(incoming, byTenant);
    }

    const key = tenant ?? "";
    let ctx = byTenant.get(key);

    if (!ctx) {
      ctx = request(incoming, tenant === undefined ? {} : { tenant });
      byTenant.set(key, ctx);
    }

    return ctx;
  };

  return extendServer<BetterExpo<M, F, E, C, P, B, V>>(server, {
    request,

    async bootstrap<T>(
      incoming: ExpoRequest,
      call: ExpoBootstrapOptions,
    ): Promise<Bootstrap<C, P, T>> {
      const { refresh, ...rest } = call;

      const ctx = await request(incoming, {
        ...(refresh === undefined ? {} : { refresh }),
        ...(rest.tenant === undefined ? {} : { tenant: rest.tenant }),
      });

      return bootstrapWith<C, P, T>(
        {
          schema: (options_) =>
            bootstrapSchema(options_, options, betterSupabase),
          evictSession: (userId) => server.evictSession(userId),
          versions: server.versions,
        },
        ctx,
        rest,
        await tenantFor(incoming, ctx, rest.tenant),
        bootMemo(incoming),
      );
    },

    async getAccess(source, accessOptions = {}) {
      if (source === null || "accessToken" in source) {
        return server.accessFor(source, accessOptions);
      }

      const explicit =
        accessOptions.tenant ?? accessOptions.bootstrap?.tenant ?? undefined;

      const ctx = await request(
        source,
        explicit === undefined ? {} : { tenant: explicit },
      );

      return accessOf(ctx, {
        tenant: (await tenantFor(source, ctx, explicit)) ?? null,
        authzVersion:
          accessOptions.bootstrap?.authzVersion ??
          snapshotOf(ctx.auth)?.authzVersion ??
          null,
        authorizer: server.authorizer,
      });
    },

    async cached(incoming, cachedOptions = {}) {
      const ctx = await contextFor(incoming, cachedOptions.tenant);
      const session = toSession(ctx.auth);
      const tenant = await tenantFor(incoming, ctx, cachedOptions.tenant);
      const snapshot = snapshotOf(ctx.auth);

      const tags = [
        ...(snapshot
          ? userSessionTags(server.authorization, snapshot.userId)
          : []),
        ...(snapshot?.sessionId ? [sessionIdTag(snapshot.sessionId)] : []),
        ...(cachedOptions.tables ?? []).flatMap((table) =>
          tableTags(table, tenant === undefined ? {} : { tenant }),
        ),
        ...(cachedOptions.tags ?? []),
      ];

      return { context: ctx, session, tenant: tenant ?? null, tags };
    },

    loader(fn, loaderOptions) {
      return async (incoming, params) => {
        if (!incoming) {
          throw new StatusError(
            500,
            'better-supabase: bsb.loader() needs a request, and static rendering has none. Turn on unstable_useServerRendering on Expo SDK 57, or read public data in a loader built with createStaticLoader from "expo-server".',
          );
        }

        const ctx = await request(incoming, loaderOptions);

        try {
          return await fn(ctx, params, incoming);
        } catch (cause) {
          if (cause instanceof DbException) {
            throw statusError(cause.error, expose);
          }

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
            return await respond(() => fn(incoming, ctx.bsb, params), {
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
      const {
        redirectTo,
        allow,
        aal,
        scopes,
        publicPaths = [],
      } = middlewareOptions;

      return async (incoming): Promise<Response | void> => {
        const resolved = toRequest(incoming);

        const ctx = await server.context(resolved, {
          refresh: refreshFor(middlewareOptions.refresh, resolved) ?? true,
        });

        const url = new URL(incoming.url);

        const target =
          redirectTo === undefined ? undefined : new URL(redirectTo, url);

        if (
          !target ||
          under(url.pathname, target.pathname) ||
          publicPaths.some((path) => under(url.pathname, path)) ||
          !guard(ctx.auth, allow, aal, scopes)
        ) {
          writeHeaders(ctx);
          handOff(
            incoming,
            ctx.resolution.cookies.length > 0
              ? ctx.resolution.requestCookies
                  .map(
                    (cookie) =>
                      `${cookie.name}=${encodeURIComponent(cookie.value)}`,
                  )
                  .join("; ")
              : undefined,
          );

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
