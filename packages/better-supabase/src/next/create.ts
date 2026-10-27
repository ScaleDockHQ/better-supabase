import { cacheLife, cacheTag, io } from "next/cache.js";
import { cookies, headers } from "next/headers.js";
import { NextResponse, after } from "next/server.js";
import { cache } from "react";

import type { AuthResolution, ResolvePhase } from "../auth/resolve.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthSession } from "../auth/view.ts";
import type {
  AnyAuthorizer,
  AuthzVersionCache,
  PermissionRef,
} from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { Result } from "../core/result.ts";
import type { DbStats } from "../core/stats.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  ActionResult,
  AuthorizeOptions,
  Unwrapped,
} from "../server/kit.ts";
import type { Settled } from "../server/respond.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
} from "../server/server-types.ts";
import type { BetterNext, NextOptions, ScopeOptions } from "./types.ts";

import { snapshotOf } from "../auth/snapshot.ts";
import { SUPPORT_COOKIE, supportCookieMaxAge } from "../auth/support-cookie.ts";
import { tenantOf, toSession } from "../auth/view.ts";
import { methodOf } from "../blocks/block-method.ts";
import { claimsOf } from "../core/claims.ts";
import { dbError } from "../core/errors.ts";
import { isList } from "../core/guards.ts";
import { isReadSet } from "../core/read-set.ts";
import { err } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { EMPTY_STATS } from "../core/stats.ts";
import { tagFor } from "../core/tags.ts";
import { bearerRequest, flushEvents, handle } from "../server/adapter.ts";
import { serverCore } from "../server/entries/core.ts";
import { outageResponse } from "../server/entries/session.ts";
import { withExtra } from "../server/extra.ts";
import {
  authorizeCaller as authorizeAuth,
  requireCaller,
  formDataObject,
} from "../server/kit.ts";
import { isPrefetch } from "../server/refresh.ts";
import { resourceRouter } from "../server/resources.ts";
import { defaultExpose, guard, settle } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import {
  invalidateAll,
  nextCache,
  nextCacheAttached,
  sessionIdTag,
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
import { recordServer } from "./record.ts";
import { resourceRoutes } from "./resources.ts";
import { authFlows } from "./sign-in.ts";
import {
  STATS_URL_HEADER,
  endedRedirect,
  shouldCheckSession,
  shouldRefresh,
} from "./support.ts";

/**
 * The Next.js adapter: proxy, Server Components, route handlers, server actions
 * and cache tags, on top of `createServer`.
 *
 * ```ts
 * export const bsb = createNext(betterSupabase);
 * ```
 */
export function createNext<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  A extends AnyAuthorizer<V> | undefined = undefined,
  B = unknown,
  V extends AuthzVersionCache = AuthzVersionCache,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: NextOptions & {
    readonly authorizer?: A;
    readonly versions?: V;
  } = {},
): BetterNext<M, F, E, C, P, PermissionRef<A>, B, V> {
  // SAFETY: a shared server was built from the same BetterSupabase, so its type parameters match.
  const base =
    (options.server as BetterServer<M, F, E, C, P, B, V> | undefined) ??
    createServer(betterSupabase, options);

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
  const statsHeader = debug?.header ?? "x-bsb-db-calls";
  const statsRoute = debug?.route ?? "/api/bsb-stats";
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
    ctx: ServerContext<M, F, E, C, P, B>,
  ): Promise<void> => {
    const writes = ctx.cookies();

    if (writes.length === 0) {
      return;
    }

    const jar = await cookies();

    for (const write of writes) {
      jar.set(write.name, write.value, write.options);
    }
  };

  /**
   * The incoming request, with the cookie header rebuilt from the cookie jar:
   * in a Server Action or a route handler the jar already holds this request's
   * writes (a sign-in, a sign-out), and the header never does.
   */
  const incomingRequest = async (): Promise<Request> => {
    const [incomingHeaders, jar] = await Promise.all([headers(), cookies()]);
    const forwarded = new Headers(incomingHeaders);

    const cookie = jar
      .getAll()
      .map(({ name, value }) => `${name}=${encodeURIComponent(value)}`)
      .join("; ");

    if (cookie === "") {
      forwarded.delete("cookie");
    } else {
      forwarded.set("cookie", cookie);
    }

    return new Request("http://next.local/", { headers: forwarded });
  };

  /**
   * The incoming request, once its dynamic APIs are awaited. Auth reads cookies
   * and then the clock: `io()` marks that as I/O for Cache Components without
   * blocking a prefetch the way `connection()` does, and awaiting `cookies()`
   * first keeps the clock read out of the static shell.
   */
  const requestScope = async (): Promise<Request> => {
    await io();
    await cookies();

    return incomingRequest();
  };

  const forget = (userId: string): void => {
    base.evictSession(userId).catch((cause: unknown) => {
      betterSupabase.events.logger.warn("Could not evict the user's session", {
        cause,
      });
    });
  };

  /**
   * The request's auth generation. A sign-in or sign-out in the request bumps
   * it and stores the committed session, so the cached reads below miss once
   * and answer from it; a render that never commits keys every read on 0.
   */
  const box = cache(
    (): {
      generation: number;
      committed:
        | {
            readonly request: Request;
            readonly resolution: AuthResolution<C, P>;
          }
        | undefined;
    } => ({ generation: 0, committed: undefined }),
  );

  /**
   * One token verification per render scope backs `context()`, `claims()` and
   * `cached()`.
   */
  const incomingAt = cache(
    async (
      _generation: number,
    ): Promise<{
      readonly request: Request;
      readonly resolution: AuthResolution<C, P>;
    }> => {
      const committed = box().committed;

      if (committed) {
        return committed;
      }

      const request = await requestScope();
      // Scopes that resolve the same token share one verification; resolve
      // then answers from the verified-token memo.
      await base.snapshot(request);

      return {
        request,
        resolution: await base.resolve(request, { refresh: false }),
      };
    },
  );

  const incoming = (): ReturnType<typeof incomingAt> =>
    incomingAt(box().generation);

  const getClaimsAt = cache(
    async (_generation: number): Promise<SessionSnapshot<C> | null> => {
      const committed = box().committed;

      return committed
        ? snapshotOf(committed.resolution.auth)
        : base.snapshot(await requestScope());
    },
  );

  const getClaims = (): Promise<SessionSnapshot<C> | null> =>
    getClaimsAt(box().generation);

  const tenantClaim = claimsOf(betterSupabase.meta).tenant;
  /** The tenant `scoped` resolved for a context, when it wasn't the claim. */
  const scopedTenants = new WeakMap<object, string>();

  const tenantFor = (
    ctx: ServerContext<M, F, E, C, P, B>,
    view: AuthSession<C, P>,
  ): string | undefined =>
    scopedTenants.get(ctx) ?? tenantOf(view, tenantClaim);

  /**
   * `requireTenant`, `roles`, `permission` and `authorize`, for the context's
   * tenant.
   */
  const authorizeCaller = <I, X>(
    ctx: ServerContext<M, F, E, C, P, B>,
    checks: AuthorizeOptions<I, C, P, boolean, unknown, X>,
    input: I,
  ): ReturnType<typeof authorizeAuth<I, C, P, X>> =>
    authorizeAuth(
      ctx.auth,
      checks,
      input,
      tenantFor(ctx, toSession(ctx.auth)),
      base.authorizer,
      ctx,
    );

  /** `null` runs `NextOptions.tenant`; a string is the caller's explicit tenant. */
  const scopedAt = cache(
    async (
      explicit: string | null,
      _generation: number,
    ): Promise<ServerContext<M, F, E, C, P, B>> => {
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

      if (tenant !== undefined) {
        scopedTenants.set(ctx, tenant);
      }

      return ctx;
    },
  );

  const current = (tenant?: string): Promise<ServerContext<M, F, E, C, P, B>> =>
    scopedAt(tenant ?? null, box().generation);

  const context = (
    first?: Request | ScopeOptions,
    contextOptions?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>> =>
    first instanceof Request
      ? base.context(first, contextOptions)
      : current(first?.tenant ?? contextOptions?.tenant);

  /** In a support session, the target's view: `impersonator` names the admin. */
  const sessionAt = cache(
    async (_generation: number): Promise<AuthSession<C, P>> =>
      toSession(
        options.support
          ? (await current()).auth
          : (await incoming()).resolution.auth,
      ),
  );

  const claims = (): Promise<AuthSession<C, P>> => sessionAt(box().generation);

  const supportCookieName =
    options.support?.options.cookie?.name ?? SUPPORT_COOKIE;

  const supportCookieOptions = {
    httpOnly: true,
    sameSite: "lax",
    path: options.support?.options.cookie?.path ?? "/",
    secure: options.support?.options.cookie?.secure ?? true,
  } as const;

  const contextFromView = async (
    view: AuthSession<C, P>,
    { token }: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P, B>> => {
    const ctx = await base.context(bearerRequest(token));

    // An expired token or an unreachable JWKS keeps its own error.
    if (ctx.auth.kind === "invalid") {
      return ctx;
    }

    const matches =
      ctx.auth.kind === "user"
        ? view.kind === "user" && view.user.id === ctx.auth.user.id
        : view.kind === ctx.auth.kind;

    if (matches) {
      return ctx;
    }

    return base.contextFor({
      kind: "invalid",
      reason: "token",
      error: dbError(
        "unauthorized",
        "The token does not belong to the session passed to contextFromSession()",
      ),
    });
  };

  function contextFromSession(
    snapshot: SessionSnapshot<C> | null,
    contextOptions?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  function contextFromSession(
    view: AuthSession<C, P>,
    tokenOptions: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  function contextFromSession(
    session: SessionSnapshot<C> | AuthSession<C, P> | null,
    sessionOptions?: ContextOptions | { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P, B>> {
    if (session !== null && "kind" in session) {
      return contextFromView(
        session,
        sessionOptions !== undefined && "token" in sessionOptions
          ? sessionOptions
          : { token: null },
      );
    }

    return base.contextFromSession(
      session,
      sessionOptions !== undefined && "token" in sessionOptions
        ? {}
        : sessionOptions,
    );
  }

  const evictSession = async (
    userId: string,
    evictOptions: { readonly tags?: readonly string[] } = {},
  ): Promise<void> => {
    invalidateAll([sessionTag(userId), ...(evictOptions.tags ?? [])]);
    await base.evictSession(userId);
  };

  const withAccounts = withExtra(base, {
    context,
    contextFromSession,
    evictSession,
    deleteAccount: ((userId, deleteOptions) =>
      base.deleteAccount(userId, deleteOptions).map((result) => {
        invalidateAll([sessionTag(userId)]);
        forget(userId);

        return result;
      })) satisfies BetterServer<M, F, E, C, P, B>["deleteAccount"],
    endSessions: ((userId) =>
      base.endSessions(userId).map((result) => {
        invalidateAll([sessionTag(userId)]);
        forget(userId);

        return result;
      })) satisfies BetterServer<M, F, E, C, P, B>["endSessions"],
    suspendAccount: ((userId, suspendOptions) =>
      base.suspendAccount(userId, suspendOptions).map((result) => {
        invalidateAll([sessionTag(userId)]);
        forget(userId);

        return result;
      })) satisfies BetterServer<M, F, E, C, P, B>["suspendAccount"],
  });

  const flows = authFlows<C, P>({
    env: () => base.env,
    auth: options.auth,
    cookieScopes: options.cookieScopes,
    request: incomingRequest,
    jar: cookies,
    current: getClaims,
    verify: (token) => base.resolve(bearerRequest(token)),
    async publish(resolution, request) {
      await base.sessions.seed(resolution.auth);
      const scope = box();
      scope.committed = { request, resolution };
      scope.generation += 1;
    },
    signedOut: (userId) => {
      invalidateAll([sessionTag(userId)]);
      forget(userId);
    },
  });

  const next: BetterNext<M, F, E, C, P, PermissionRef<A>, B, V> = extendServer<
    BetterNext<M, F, E, C, P, PermissionRef<A>, B, V>
  >(withAccounts, {
    claims,
    getClaims,

    async cached(cachedOptions = {}) {
      const [view, ctx] = await Promise.all([
        claims(),
        current(cachedOptions.tenant),
      ]);

      const life = cachedOptions.life;
      const stale = sessionStale(view, life);
      cacheLife({
        stale: life?.stale === undefined ? stale : Math.min(stale, life.stale),
        ...(life?.revalidate === undefined
          ? {}
          : { revalidate: life.revalidate }),
        ...(life?.expire === undefined ? {} : { expire: life.expire }),
      });
      const tables = cachedOptions.tables ?? [];
      const tenant = tables.length > 0 ? tenantFor(ctx, view) : undefined;
      const first = tables[0];

      const claimed =
        ctx.auth.kind === "user" ? ctx.auth.claims["session_id"] : undefined;

      const sessionId = typeof claimed === "string" ? claimed : undefined;

      const tags = [
        ...(view.kind === "user" ? [sessionTag(view.user.id)] : []),
        ...(sessionId === undefined ? [] : [sessionIdTag(sessionId)]),
        ...(ctx.support ? [supportTag(ctx.support.session.id)] : []),
        ...(cachedOptions.tags ?? []),
        ...tables.flatMap((table) =>
          tableTags(table, tenant === undefined ? {} : { tenant }),
        ),
        ...(first !== undefined && cachedOptions.id !== undefined
          ? [tagFor(first, cachedOptions.id)]
          : []),
      ];

      if (tags.length > 0) {
        cacheTag(...tags);
      }

      return withExtra(ctx, { session: view });
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
      let authMs = 0;
      const phases: Partial<Record<ResolvePhase, number>> = {};

      // `before` (i18n rewrites, redirects) and auth run on the original request.
      const sessionCheck =
        proxyOptions.verifySession === true ? {} : proxyOptions.verifySession;

      const verifySession =
        sessionCheck !== undefined && shouldCheckSession(request, sessionCheck);

      const [early, resolution] = await Promise.all([
        proxyOptions.before?.(request),
        base
          .resolve(request, {
            refresh: shouldRefresh(request),
            ...(verifySession ? { verifySession } : {}),
            ...(proxyOptions.leeway === undefined
              ? {}
              : { leeway: proxyOptions.leeway }),
            ...(proxyOptions.serverTiming
              ? {
                  onTiming: (phase: ResolvePhase, ms: number) => {
                    phases[phase] = (phases[phase] ?? 0) + ms;
                  },
                }
              : {}),
          })
          .then((resolved) => {
            authMs = performance.now() - started;

            return resolved;
          }),
      ]);

      // A refreshed token is already verified: the render reads it from the
      // memo instead of verifying it again.
      if (resolution.cookies.length > 0) {
        await base.sessions.seed(resolution.auth);
      }

      const rendersSignedOut =
        proxyOptions.onExpiredPrefetch === "render" &&
        resolution.auth.kind === "none" &&
        resolution.auth.reason === "expired" &&
        isPrefetch(request);

      const protectMethods = proxyOptions.protectMethods;

      const runsProtect =
        protectMethods === true
          ? true
          : (protectMethods ?? ["GET", "HEAD"]).includes(request.method);

      const ended =
        resolution.sessionVerified === false &&
        sessionCheck?.redirect !== undefined &&
        request.nextUrl.pathname !== sessionCheck.redirect
          ? endedRedirect(
              request,
              sessionCheck.redirect,
              resolution.reason === "user_banned"
                ? (sessionCheck.reasons?.banned ?? "user_banned")
                : (sessionCheck.reasons?.ended ?? "session_not_found"),
            )
          : undefined;

      const custom =
        ended ??
        (await outageResponse(
          proxyOptions.onAuthOutage,
          resolution,
          request,
          betterSupabase.events.logger,
        )) ??
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
              (cookie) => `${cookie.name}=${encodeURIComponent(cookie.value)}`,
            )
            .join("; ");
        }

        if (id) {
          forwarded[REQUEST_ID_HEADER] = id;
        }

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

        if (replaced) {
          response = mutableResponse(replaced);
        }
      }

      if (proxyOptions.serverTiming) {
        response.headers.append(
          "server-timing",
          serverTimingValue({
            "bsb-proxy": performance.now() - started,
            "bsb-auth": authMs,
            ...Object.fromEntries(
              Object.entries(phases).map(([phase, ms]) => [`bsb-${phase}`, ms]),
            ),
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
        let current: ServerContext<M, F, E, C, P, B> | undefined;
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

              if ("kind" in caller) {
                return err(caller);
              }

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
          if (current) {
            await writeCookies(current);
          }

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
        ...(base.authorizer === undefined
          ? {}
          : { authorizer: base.authorizer }),
      });

      return resourceRoutes(async (request) => {
        const route = router.match(request);

        if (route instanceof Response) {
          return route;
        }

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

        if (denied) {
          return { ok: false, data: null, error: denied };
        }

        let parsed: unknown =
          input instanceof FormData ? formDataObject(input) : input;

        if (actionOptions.input) {
          const checked = await validate(actionOptions.input, parsed, "input");

          if (!checked.ok) {
            return { ok: false, data: null, error: checked.error };
          }

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

        if ("kind" in caller) {
          return { ok: false, data: null, error: caller };
        }

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
        base.authorizer,
        ctx,
      );

      if ("kind" in caller) {
        interrupt(caller);
      }

      // SAFETY: requireTenant refused a missing tenant.
      return withExtra(ctx, caller) as never;
    },

    async startSupport(request) {
      const { resolution } = await incoming();
      const started = await base.support.start(resolution.auth, request);
      flushAfter();

      if (!started.ok) {
        return { ok: false, data: null, error: started.error };
      }

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
      jar.delete({ name: supportCookieName, path: supportCookieOptions.path });

      if (!id) {
        return { ok: true, data: { ended: false }, error: null };
      }

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

    ...flows,

    tag(table, id, tagOptions = {}) {
      cacheTag(
        ...tableTags(table, tagOptions),
        ...(id === undefined ? [] : [tagFor(table, id)]),
      );
    },

    tags(target, tagOptions = {}) {
      const specs = isReadSet(target)
        ? Object.values(target.specs)
        : isList(target)
          ? target
          : [target];

      const tags = new Set<string>();

      for (const spec of specs) {
        for (const table of betterSupabase.tablesOf(spec)) {
          for (const tag of tableTags(table, tagOptions)) {
            tags.add(tag);
          }
        }

        const [id] = spec.args;

        if (
          spec.method === "get" &&
          (typeof id === "string" || typeof id === "number")
        ) {
          tags.add(tagFor(spec.table, id));
        }
      }

      cacheTag(...tags);
    },

    blockAction: (client, method, blockOptions) => {
      const run = next.action(
        blockOptions,
        async (input, ctx): Promise<Result<unknown>> => {
          const call = methodOf(client(ctx), method);

          // SAFETY: BlockActionArgs makes `args` required unless the method
          // takes the validated input as its only argument.
          const args = (blockOptions.args?.(input, ctx) ?? [
            input,
          ]) as readonly unknown[];

          return call(...args);
        },
      );

      // SAFETY: the method's `Result` carries `BlockDataOf<Cl, K>`.
      return run as never;
    },

    record: (type) => recordServer(next, type),
  });

  return next;
}
