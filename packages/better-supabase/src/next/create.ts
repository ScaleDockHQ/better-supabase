import { cacheLife, cacheTag, io } from "next/cache.js";
import { cookies, headers } from "next/headers.js";
import { NextResponse, after } from "next/server.js";
import { cache } from "react";

import type { AuthResolution } from "../auth/resolve.ts";
import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
} from "../server/server-types.ts";
import type { BetterNext, NextOptions, ScopeOptions } from "./types.ts";

import { SUPPORT_COOKIE, supportCookieMaxAge } from "../auth/support-cookie.ts";
import { tenantOf, toSession, type AuthSession } from "../auth/view.ts";
import { claimsOf } from "../core/claims.ts";
import { dbError } from "../core/errors.ts";
import { isList } from "../core/guards.ts";
import { isReadSet } from "../core/read-set.ts";
import { err } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { EMPTY_STATS, type DbStats } from "../core/stats.ts";
import { tagFor } from "../core/tags.ts";
import { bearerRequest, flushEvents, handle } from "../server/adapter.ts";
import { serverCore } from "../server/entries/core.ts";
import { withExtra } from "../server/extra.ts";
import {
  authorizeCaller as authorizeAuth,
  requireCaller,
  formDataObject,
  type ActionResult,
  type AuthorizeOptions,
  type Unwrapped,
} from "../server/kit.ts";
import { isPrefetch } from "../server/refresh.ts";
import { resourceRouter } from "../server/resources.ts";
import {
  defaultExpose,
  guard,
  settle,
  type Settled,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import {
  invalidateAll,
  nextCache,
  nextCacheAttached,
  sessionStale,
  sessionTag,
  supportTag,
  tableTags,
} from "./cache.ts";
import {
  REQUEST_ID_HEADER,
  formatStats,
  sharedCollector,
} from "./collector.ts";
import { interrupt, rethrowNextControlFlow } from "./control-flow.ts";
import {
  isRedirect,
  mutableResponse,
  overrideRequestHeaders,
  serverTimingValue,
} from "./proxy.ts";
import { resourceRoutes } from "./resources.ts";
import {
  STATS_URL_HEADER,
  endedRedirect,
  shouldCheckSession,
  shouldRefresh,
} from "./support.ts";

/**
 * The Next.js adapter: proxy, Server Components, route handlers, server
 * actions and cache tags, on top of `createServer`.
 *
 * ```ts
 * export const bs = createNext(betterSupabase);
 * ```
 */
export function createNext<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  A extends AnyAuthorizer | undefined = undefined,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: NextOptions & { readonly authorizer?: A } = {},
): BetterNext<M, F, E, C, P, PermissionRef<A>> {
  const base = createServer(betterSupabase, options);
  const core = serverCore(base);
  const expose = options.exposeErrors ?? defaultExpose();

  if (
    options.cacheTags !== false &&
    !nextCacheAttached.has(betterSupabase.events)
  ) {
    nextCacheAttached.add(betterSupabase.events);
    betterSupabase.cache(nextCache());
  }

  const debug = options.debug;
  const statsHeader = debug?.header ?? "x-bs-db-calls";
  const statsRoute = debug?.route ?? "/api/bs-stats";
  const development = process.env["NODE_ENV"] === "development";
  const collector = debug?.enabled
    ? sharedCollector({
        logger: betterSupabase.events.logger,
        warn: development,
        ...(debug.budget ? { budget: debug.budget } : {}),
      })
    : undefined;
  const statsFor = (request: Request): ContextOptions => {
    const id = collector && request.headers.get(REQUEST_ID_HEADER);
    return id ? { stats: collector.recorderFor(id) } : {};
  };

  const waitUntil = (work: Promise<unknown>): void => {
    try {
      after(() => work);
    } catch (cause) {
      // after() only works inside a request scope; the sends still run.
      betterSupabase.events.logger.warn(
        "after() is unavailable; event sends may be cut off",
        { cause },
      );
    }
  };
  /** Keeps the function alive for event sink sends the handler started. */
  const flushAfter = (): void => {
    flushEvents(betterSupabase, waitUntil);
  };
  /** Sets the context's cookies (the replica pin) through Next's cookie jar. */
  const writeCookies = async (
    ctx: ServerContext<M, F, E, C, P>,
  ): Promise<void> => {
    const writes = ctx.cookies();
    if (writes.length === 0) return;
    const jar = await cookies();
    for (const write of writes) jar.set(write.name, write.value, write.options);
  };

  const incomingRequest = async (): Promise<Request> =>
    new Request("http://next.local/", {
      headers: new Headers(await headers()),
    });

  /** One token verification per render scope backs `context()`, `session()` and `cached()`. */
  const incoming = cache(
    async (): Promise<{
      readonly request: Request;
      readonly resolution: AuthResolution<C, P>;
    }> => {
      // Auth reads cookies and the clock. `io()` marks that as I/O for
      // Cache Components without blocking a prefetch the way `connection()` does.
      await io();
      const request = await incomingRequest();
      return {
        request,
        resolution: await base.resolve(request, { refresh: false }),
      };
    },
  );

  const tenantClaim = claimsOf(betterSupabase.meta).tenant;
  /** The tenant `scoped` resolved for a context, when it wasn't the claim. */
  const scopedTenants = new WeakMap<object, string>();
  const tenantFor = (
    ctx: ServerContext<M, F, E, C, P>,
    view: AuthSession<C, P>,
  ): string | undefined =>
    scopedTenants.get(ctx) ?? tenantOf(view, tenantClaim);
  /** `requireTenant`, `roles`, `permission` and `authorize`, for the context's tenant. */
  const authorizeCaller = <I>(
    ctx: ServerContext<M, F, E, C, P>,
    checks: AuthorizeOptions<I, C, P, boolean>,
    input: I,
  ): ReturnType<typeof authorizeAuth<I, C, P>> =>
    authorizeAuth(
      ctx.auth,
      checks,
      input,
      tenantFor(ctx, toSession(ctx.auth)),
      options.authorizer,
    );

  /** `null` runs `NextOptions.tenant`; a string is the caller's explicit tenant. */
  const scoped = cache(
    async (explicit: string | null): Promise<ServerContext<M, F, E, C, P>> => {
      const { request, resolution } = await incoming();
      const [tenant, support] = await Promise.all([
        explicit ?? options.tenant?.(request, resolution.auth),
        base.support.current(request, resolution.auth),
      ]);
      // Both tenants take the resolver's path, so they get the same checks.
      const ctx = core.context(
        resolution,
        request,
        { ...statsFor(request), ...(support ? { support } : {}) },
        tenant,
      );
      if (tenant !== undefined) scopedTenants.set(ctx, tenant);
      return ctx;
    },
  );
  const current = (tenant?: string): Promise<ServerContext<M, F, E, C, P>> =>
    scoped(tenant ?? null);

  const context = (
    first?: Request | ScopeOptions,
    contextOptions?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P>> =>
    first instanceof Request
      ? base.context(first, contextOptions)
      : current(first?.tenant ?? contextOptions?.tenant);

  /** In a support session, the target's view: `impersonator` names the admin. */
  const session = cache(async (): Promise<AuthSession<C, P>> =>
    toSession(
      options.support
        ? (await current()).auth
        : (await incoming()).resolution.auth,
    ),
  );

  const supportCookieName =
    options.support?.options.cookie?.name ?? SUPPORT_COOKIE;
  const supportCookieOptions = {
    httpOnly: true,
    sameSite: "lax",
    path: options.support?.options.cookie?.path ?? "/",
    secure: options.support?.options.cookie?.secure ?? true,
  } as const;

  const contextForSession = async (
    view: AuthSession<C, P>,
    { token }: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P>> => {
    const ctx = await base.context(bearerRequest(token));
    // An expired token or an unreachable JWKS keeps its own error.
    if (ctx.auth.kind === "invalid") return ctx;
    const matches =
      ctx.auth.kind === "user"
        ? view.kind === "user" && view.user.id === ctx.auth.user.id
        : view.kind === ctx.auth.kind;
    if (matches) return ctx;
    return base.contextFor({
      kind: "invalid",
      reason: "token",
      error: dbError(
        "unauthorized",
        "The token does not belong to the session passed to contextForSession()",
      ),
    });
  };

  const withAccounts = withExtra(base, {
    context,
    deleteAccount: ((userId, deleteOptions) =>
      base.deleteAccount(userId, deleteOptions).map((result) => {
        invalidateAll([sessionTag(userId)]);
        return result;
      })) satisfies BetterServer<M, F, E, C, P>["deleteAccount"],
    endSessions: ((userId) =>
      base.endSessions(userId).map((result) => {
        invalidateAll([sessionTag(userId)]);
        return result;
      })) satisfies BetterServer<M, F, E, C, P>["endSessions"],
    suspendAccount: ((userId, suspendOptions) =>
      base.suspendAccount(userId, suspendOptions).map((result) => {
        invalidateAll([sessionTag(userId)]);
        return result;
      })) satisfies BetterServer<M, F, E, C, P>["suspendAccount"],
  });

  return extendServer<BetterNext<M, F, E, C, P, PermissionRef<A>>>(
    withAccounts,
    {
      session,
      contextForSession,

      async cached(cachedOptions = {}) {
        const [view, ctx] = await Promise.all([
          session(),
          current(cachedOptions.tenant),
        ]);
        const life = cachedOptions.life;
        const stale = sessionStale(view, life);
        cacheLife({
          stale:
            life?.stale === undefined ? stale : Math.min(stale, life.stale),
          ...(life?.revalidate === undefined
            ? {}
            : { revalidate: life.revalidate }),
          ...(life?.expire === undefined ? {} : { expire: life.expire }),
        });
        const tables = cachedOptions.tables ?? [];
        const tenant = tables.length > 0 ? tenantFor(ctx, view) : undefined;
        const first = tables[0];
        const tags = [
          ...(view.kind === "user" ? [sessionTag(view.user.id)] : []),
          ...(ctx.support ? [supportTag(ctx.support.session.id)] : []),
          ...(cachedOptions.tags ?? []),
          ...tables.flatMap((table) =>
            tableTags(table, tenant === undefined ? {} : { tenant }),
          ),
          ...(first !== undefined && cachedOptions.id !== undefined
            ? [tagFor(first, cachedOptions.id)]
            : []),
        ];
        if (tags.length > 0) cacheTag(...tags);
        return withExtra(ctx, { session: view });
      },

      invalidateSession(userId, invalidateOptions = {}) {
        invalidateAll([sessionTag(userId), ...(invalidateOptions.tags ?? [])]);
      },

      async liveCount(spec, db) {
        const runner = db ?? (await current()).db;
        const result = await runner.$run(spec);
        return {
          spec,
          count:
            result.ok && typeof result.data === "number" ? result.data : null,
          at: Date.now(),
        };
      },

      async proxy(request, proxyOptions = {}) {
        const started = performance.now();
        const id = collector ? crypto.randomUUID() : undefined;
        let verifyMs = 0;
        // `before` (i18n rewrites, redirects) and auth run on the original request.
        const sessionCheck =
          proxyOptions.endedSession === true ? {} : proxyOptions.endedSession;
        const checkSession =
          sessionCheck !== undefined &&
          shouldCheckSession(request, sessionCheck);
        const [early, resolution] = await Promise.all([
          proxyOptions.before?.(request),
          base
            .resolve(request, {
              refresh: shouldRefresh(request),
              ...(checkSession ? { checkSession } : {}),
            })
            .then((resolved) => {
              verifyMs = performance.now() - started;
              return resolved;
            }),
        ]);
        const rendersSignedOut =
          proxyOptions.expiredPrefetch === "render" &&
          resolution.auth.kind === "anon" &&
          resolution.auth.reason === "expired" &&
          isPrefetch(request);
        const protectMethods = proxyOptions.protectMethods;
        const runsProtect =
          protectMethods === true
            ? true
            : (protectMethods ?? ["GET", "HEAD"]).includes(request.method);
        const ended =
          resolution.sessionEnded === true &&
          sessionCheck?.redirect !== undefined &&
          request.nextUrl.pathname !== sessionCheck.redirect
            ? endedRedirect(
                request,
                sessionCheck.redirect,
                resolution.sessionEndedReason === "banned"
                  ? (sessionCheck.reasons?.banned ?? "account_banned")
                  : (sessionCheck.reasons?.ended ?? "session_ended"),
              )
            : undefined;
        const custom =
          ended ??
          (rendersSignedOut || !runsProtect
            ? undefined
            : await proxyOptions.protect?.(resolution.auth, request));
        const initial = custom ?? early;
        if (
          !initial &&
          resolution.cookies.length === 0 &&
          !id &&
          !proxyOptions.after &&
          !proxyOptions.serverTiming
        ) {
          flushAfter();
          return NextResponse.next();
        }

        let response = resolution.apply(
          mutableResponse(initial ?? NextResponse.next()),
        );
        if (!custom && !isRedirect(response)) {
          const forwarded: Record<string, string> = {};
          if (resolution.cookies.length > 0) {
            forwarded["cookie"] = resolution.requestCookies
              .map(
                (cookie) =>
                  `${cookie.name}=${encodeURIComponent(cookie.value)}`,
              )
              .join("; ");
          }
          if (id) forwarded[REQUEST_ID_HEADER] = id;
          if (Object.keys(forwarded).length > 0 || early) {
            overrideRequestHeaders(response, request, forwarded);
          }
        }
        if (id) {
          response.headers.set(REQUEST_ID_HEADER, id);
          response.headers.set(STATS_URL_HEADER, `${statsRoute}?id=${id}`);
        }
        if (proxyOptions.after) {
          const replaced = await proxyOptions.after(response, resolution.auth);
          if (replaced) response = mutableResponse(replaced);
        }
        if (proxyOptions.serverTiming) {
          response.headers.append(
            "server-timing",
            serverTimingValue({
              "bs-proxy": performance.now() - started,
              "bs-verify": verifyMs,
            }),
          );
        }
        // A refresh or sign-out in `resolve`, or `protect`, can start sink sends.
        flushAfter();
        return response;
      },

      route(handler, guardOptions = {}) {
        return async (request, segment) => {
          let stats: (() => DbStats) | undefined;
          let current: ServerContext<M, F, E, C, P> | undefined;
          let response: Response;
          try {
            response = await handle(
              base,
              request,
              async (ctx) => {
                current = ctx;
                stats = () => ctx.stats();
                const [params, caller] = await Promise.all([
                  segment.params,
                  authorizeCaller(ctx, guardOptions, request),
                ]);
                if ("kind" in caller) return err(caller);
                // SAFETY: requireTenant refused a missing tenant.
                return handler(
                  request,
                  withExtra(ctx, { ...caller, params }) as never,
                );
              },
              {
                ...guardOptions,
                expose,
                instance: request.nextUrl.pathname,
                context: statsFor(request),
                waitUntil,
                // redirect(), notFound() and dynamic-rendering bailouts are Next's to handle.
                rethrow: rethrowNextControlFlow,
              },
            );
          } catch (cause) {
            // Next builds the redirect response itself and adds the jar's cookies to it.
            if (current) await writeCookies(current);
            throw cause;
          }
          if (collector && stats) {
            try {
              response.headers.set(statsHeader, formatStats(stats()));
            } catch {
              // A handler returned a Response with immutable headers.
            }
          }
          return response;
        };
      },

      resources(map, resourcesOptions = {}) {
        const { basePath, ...guardOptions } = resourcesOptions;
        const router = resourceRouter(betterSupabase, map, {
          ...(basePath === undefined ? {} : { basePath }),
          ...(options.authorizer === undefined
            ? {}
            : { authorizer: options.authorizer }),
        });
        return resourceRoutes(async (request) => {
          const route = router.match(request);
          if (route instanceof Response) return route;
          return handle(
            base,
            request,
            (ctx) =>
              route.handler.serve(request, ctx.db, route.segments, {
                instance: route.instance,
                expose,
              }),
            {
              ...guardOptions,
              expose,
              instance: route.instance,
              context: statsFor(request),
              waitUntil,
              rethrow: rethrowNextControlFlow,
            },
          );
        });
      },

      debugRoute() {
        return (request) => {
          const id = new URL(request.url).searchParams.get("id");
          if (!collector || !id) {
            return Promise.resolve(
              Response.json(
                { error: collector ? "missing ?id=" : "debug is off" },
                { status: 404, headers: { "cache-control": "no-store" } },
              ),
            );
          }
          // A render served from private caches never records: it made no calls.
          const stats = collector.get(id) ?? EMPTY_STATS;
          return Promise.resolve(
            Response.json(stats, {
              headers: {
                [statsHeader]: formatStats(stats),
                "cache-control": "no-store",
              },
            }),
          );
        };
      },

      action(actionOptions, fn) {
        type Out = ActionResult<Unwrapped<Awaited<ReturnType<typeof fn>>>>;
        return async (input) => {
          // With a per-input tenant the context waits for the input, so the
          // guard reads the verified caller instead of building a context for
          // `NextOptions.tenant` it would throw away. Support sessions swap the
          // caller in the context, so they keep the context's view.
          const early =
            actionOptions.tenant && !options.support
              ? undefined
              : await current();
          const denied = guard(
            early?.auth ?? (await incoming()).resolution.auth,
            actionOptions.allow,
            actionOptions.aal,
            actionOptions.scopes,
          );
          if (denied) return { ok: false, data: null, error: denied };
          let parsed: unknown =
            input instanceof FormData ? formDataObject(input) : input;
          if (actionOptions.input) {
            const checked = await validate(
              actionOptions.input,
              parsed,
              "input",
            );
            if (!checked.ok)
              return { ok: false, data: null, error: checked.error };
            parsed = checked.data;
          }
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema.
          const tenant = actionOptions.tenant?.(parsed as never);
          const ctx =
            tenant === undefined
              ? (early ?? (await current()))
              : await current(tenant);
          // SAFETY: as above, parsed is the action's input.
          const caller = await authorizeCaller(
            ctx,
            actionOptions,
            parsed as never,
          );
          if ("kind" in caller) return { ok: false, data: null, error: caller };
          const scope = ctx;
          let settled: Settled;
          try {
            // SAFETY: parsed is the validated input, or the raw input when the
            // action has no schema; requireTenant refused a missing tenant.
            settled = await settle(() =>
              fn(parsed as never, withExtra(scope, caller) as never),
            );
          } finally {
            // Also when redirect() or notFound() follows a write.
            flushAfter();
            await writeCookies(ctx);
          }
          // SAFETY: Out is the Result of the action's return type, which both branches build.
          return (
            settled.ok
              ? { ok: true, data: settled.data, error: null }
              : { ok: false, data: null, error: settled.error }
          ) as Out;
        };
      },

      require: async (requireOptions = {}) => {
        const ctx = await current(requireOptions.tenant);
        const caller = await requireCaller(
          ctx.auth,
          requireOptions,
          tenantFor(ctx, toSession(ctx.auth)),
          options.authorizer,
        );
        if ("kind" in caller) interrupt(caller);
        // SAFETY: requireTenant refused a missing tenant.
        return withExtra(ctx, caller) as never;
      },

      async startSupport(request) {
        const { resolution } = await incoming();
        const started = await base.support.start(resolution.auth, request);
        flushAfter();
        if (!started.ok) return { ok: false, data: null, error: started.error };
        const { session: support } = started.data;
        (await cookies()).set(supportCookieName, support.id, {
          ...supportCookieOptions,
          maxAge: supportCookieMaxAge(support),
        });
        if (resolution.auth.kind === "user") {
          invalidateAll([sessionTag(resolution.auth.user.id)]);
        }
        return {
          ok: true,
          data: {
            sessionId: support.id,
            targetUserId: support.targetUserId,
            readOnly: support.readOnly,
            expiresAt: support.expiresAt.toString(),
          },
          error: null,
        };
      },

      async stopSupport() {
        const { request, resolution } = await incoming();
        const jar = await cookies();
        const id = base.support.sessionIdOf(request);
        jar.delete({
          name: supportCookieName,
          path: supportCookieOptions.path,
        });
        if (!id) return { ok: true, data: { ended: false }, error: null };
        const stopped = await base.support.stop(resolution.auth, id);
        flushAfter();
        invalidateAll([
          supportTag(id),
          ...(resolution.auth.kind === "user"
            ? [sessionTag(resolution.auth.user.id)]
            : []),
        ]);
        return stopped.ok
          ? { ok: true, data: { ended: stopped.data.ended }, error: null }
          : { ok: false, data: null, error: stopped.error };
      },

      cacheTag(table, id, tagOptions = {}) {
        cacheTag(
          ...tableTags(table, tagOptions),
          ...(id === undefined ? [] : [tagFor(table, id)]),
        );
      },

      cacheTags(target, tagOptions = {}) {
        const specs = isReadSet(target)
          ? Object.values(target.specs)
          : isList(target)
            ? target
            : [target];
        const tags = new Set<string>();
        for (const spec of specs) {
          for (const table of betterSupabase.tablesOf(spec))
            for (const tag of tableTags(table, tagOptions)) tags.add(tag);
          const [id] = spec.args;
          if (
            spec.method === "findById" &&
            (typeof id === "string" || typeof id === "number")
          ) {
            tags.add(tagFor(spec.table, id));
          }
        }
        cacheTag(...tags);
      },
    },
  );
}
