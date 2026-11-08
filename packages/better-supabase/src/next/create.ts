import { cacheLife, cacheTag, io } from "next/cache.js";
import { redirect } from "next/dist/client/components/redirect.js";
import { cookies } from "next/headers.js";
import { cache } from "react";

import type { AuthResolution } from "../auth/resolve.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthSession } from "../auth/view.ts";
import type {
  AnyAuthorizer,
  AuthzVersionCache,
  PermissionRef,
} from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { ReadSet, ReadSetResult } from "../core/read-set.ts";
import type { DbStats } from "../core/stats.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BootstrapRow } from "../server/bootstrap.ts";
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
import type {
  Bootstrap,
  BootstrapOptions,
  BetterNext,
  CachedOptions,
  CacheScope,
  NextOptions,
  ScopeOptions,
} from "./types.ts";

import { markSessionEnded } from "../auth/ended.ts";
import { isSessionSnapshot, snapshotOf } from "../auth/snapshot.ts";
import { SUPPORT_COOKIE, supportCookieMaxAge } from "../auth/support-cookie.ts";
import { tenantOf, toSession } from "../auth/view.ts";
import { claimsOf } from "../core/claims.ts";
import { dbError } from "../core/errors.ts";
import { isList } from "../core/guards.ts";
import { isReadSet, readSetTables } from "../core/read-set.ts";
import { err } from "../core/result.ts";
import { isQuerySpec } from "../core/spec.ts";
import { validate } from "../core/standard.ts";
import { EMPTY_STATS } from "../core/stats.ts";
import { tagFor } from "../core/tags.ts";
import { adapterBase } from "../server/adapter-base.ts";
import { bearerRequest, handle } from "../server/adapter.ts";
import {
  accessOf,
  bootstrapSchema,
  bootstrapWith,
  mapBootstrapMemo,
} from "../server/bootstrap.ts";
import { serverCore } from "../server/entries/core.ts";
import { withExtra } from "../server/extra.ts";
import {
  authorizeCaller as authorizeAuth,
  requireCaller,
  formDataObject,
} from "../server/kit.ts";
import { resourceRouter } from "../server/resources.ts";
import { guard, settle } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import {
  blockActionOf,
  validateBound,
  withReadSetTables,
} from "./action-bound.ts";
import {
  invalidateAll,
  nextCache,
  nextCacheAttached,
  supportTag,
  tableTags,
} from "./cache.ts";
import { logActionStats, requestIdOf, formatStats } from "./collector.ts";
import { interrupt, rethrowNextControlFlow } from "./control-flow.ts";
import { applyCacheEntry, awaitStage } from "./entry.ts";
import { incomingRequest } from "./incoming-request.ts";
import { proxyHandler } from "./proxy-handler.ts";
import { proxyRuntime } from "./proxy-runtime.ts";
import { recordAtServer, recordServer } from "./record.ts";
import { handOff, takeHandoff } from "./remote-handoff.ts";
import { adminForRequest, verifyOption } from "./request-stats.ts";
import { resourceRoutes } from "./resources.ts";
import { cacheKeyOf, parkUntilResponseEnds } from "./session-handle.ts";
import { refreshCallerCache, userSessionTags } from "./session-tags.ts";
import { authFlows } from "./sign-in.ts";
import { taintObject, taintResolution, taintedAdmin } from "./taint.ts";
import { gateUserOf } from "./user.ts";
import { withContextFactory } from "./with-context.ts";

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
): BetterNext<M, F, E, C, P, PermissionRef<A>, B, V, D> {
  // SAFETY: a shared server was built from the same BetterSupabase, so its type parameters match.
  const base =
    (options.server as BetterServer<M, F, E, C, P, B, V> | undefined) ??
    createServer(betterSupabase, options);

  const core = serverCore(base);
  const { expose } = adapterBase(base, options);

  if (
    options.cacheTags !== false &&
    !nextCacheAttached.has(betterSupabase.events)
  ) {
    nextCacheAttached.add(betterSupabase.events);
    betterSupabase.cache(nextCache());
  }

  const {
    collector,
    statsHeader,
    statsRoute,
    development,
    waitUntil,
    flushAfter,
  } = proxyRuntime(betterSupabase, options);

  const statsFor = (request: Request): ContextOptions => {
    const id = collector && requestIdOf(request.headers);

    return id ? { stats: collector.recorderFor(id) } : {};
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

  const userTags = (userId: string): readonly string[] =>
    userSessionTags(base.authorization, userId);

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
      const verify = verifyOption(statsFor(request).stats);

      // Scopes that resolve the same token share one verification through the
      // verified-token memo, so resolve is the only pass.
      const resolution = await base.resolve(request, {
        refresh: false,
        ...verify,
      });

      taintResolution(resolution, options.auth?.cookie?.name, base.env.url);

      return { request, resolution };
    },
  );

  const incoming = (): ReturnType<typeof incomingAt> =>
    incomingAt(box().generation);

  const getClaimsAt = cache(
    async (generation: number): Promise<SessionSnapshot<C> | null> =>
      snapshotOf((await incomingAt(generation)).resolution.auth),
  );

  const getClaims = (): Promise<SessionSnapshot<C> | null> =>
    getClaimsAt(box().generation);

  const tenantClaim = claimsOf(betterSupabase.meta).tenant;

  /**
   * A `next/root-params` getter's value; `undefined` without the getter and
   * outside a render (actions and route handlers have no root params).
   */
  const rootParam = async (
    getter: (() => Promise<string | undefined>) | undefined,
  ): Promise<string | undefined> => {
    if (!getter) {
      return undefined;
    }

    try {
      return await getter();
    } catch {
      return undefined;
    }
  };

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
        explicit ??
          (options.tenant
            ? options.tenant(request, resolution.auth)
            : rootParam(options.rootParams?.tenant)),
        base.support.current(request, resolution.auth),
      ]);

      // Both tenants take the resolver's path, so they get the same checks.
      const ctx = core.context(
        resolution,
        request,
        { ...statsFor(request), ...(support ? { support } : {}) },
        tenant,
      );

      taintObject(
        "better-supabase: the server context never goes to the client.",
        ctx,
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

  /**
   * Both read the clock to judge a token's expiry: `resolve` for a cookie
   * session's freshness, `contextFromSession` for a parked snapshot. During a
   * runtime prefetch render the cookies are available, so awaiting them does
   * not keep the read out of the prerender; `io()` suspends there until a real
   * request, so a prerender never judges expiry and never treats an expired
   * session as live. In a request, in a cache scope and outside Next it
   * resolves at once.
   */
  const resolveAtRequest: BetterServer<M, F, E, C, P, B>["resolve"] = async (
    request,
    resolveOptions,
  ) => {
    await io();

    return base.resolve(request, resolveOptions);
  };

  const contextFromSession = async (
    snapshot: SessionSnapshot<C> | null,
    contextOptions?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>> => {
    if (snapshot !== null && snapshot.expiresAt !== null) {
      await io();
    }

    return base.contextFromSession(snapshot, contextOptions);
  };

  const evictSession = async (
    userId: string,
    evictOptions: { readonly tags?: readonly string[] } = {},
  ): Promise<void> => {
    invalidateAll([...userTags(userId), ...(evictOptions.tags ?? [])]);
    await base.evictSession(userId);
  };

  const withAccounts = withExtra(base, {
    context,
    admin: taintedAdmin(
      adminForRequest(
        (adminContext, adminOptions) => base.admin(adminContext, adminOptions),
        (request) => statsFor(request).stats,
      ),
    ),
    contextFromSession,
    resolve: resolveAtRequest,
    evictSession,
    deleteAccount: ((userId, deleteOptions) =>
      base.deleteAccount(userId, deleteOptions).map((result) => {
        invalidateAll(userTags(userId));
        forget(userId);

        return result;
      })) satisfies BetterServer<M, F, E, C, P, B>["deleteAccount"],
    endSessions: ((userId) =>
      base.endSessions(userId).map((result) => {
        invalidateAll(userTags(userId));
        forget(userId);

        return result;
      })) satisfies BetterServer<M, F, E, C, P, B>["endSessions"],
    suspendAccount: ((userId, suspendOptions) =>
      base.suspendAccount(userId, suspendOptions).map((result) => {
        invalidateAll(userTags(userId));
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
      invalidateAll(userTags(userId));
      forget(userId);
    },
  });

  /**
   * The context of a cache scope: the request's in `'use cache: private'`, the
   * handed-off snapshot's in `'use cache: remote'`.
   */
  const scopeOf = async (
    cachedOptions: CachedOptions,
  ): Promise<{
    readonly ctx: ServerContext<M, F, E, C, P, B>;
    readonly view: AuthSession<C, P>;
    readonly scope: CacheScope;
    readonly tenant: string | undefined;
  }> => {
    const handle =
      cachedOptions.scope === "remote" ? undefined : cachedOptions.session;

    const handed = handle ? takeHandoff<C>(handle) : undefined;

    if (handle && handed) {
      const ctx = await base.contextFromSession(
        handed,
        handle.tenant === null ? {} : { tenant: handle.tenant },
      );

      const view = toSession(ctx.auth);

      return { ctx, view, scope: "private", tenant: tenantFor(ctx, view) };
    }

    if (cachedOptions.scope !== "remote") {
      const [view, ctx] = await Promise.all([
        claims(),
        current(cachedOptions.tenant),
      ]);

      return { ctx, view, scope: "private", tenant: tenantFor(ctx, view) };
    }

    const { key } = cachedOptions;
    const tenant = key.tenant ?? undefined;
    const snapshot = takeHandoff<C>(key);

    const ctx = snapshot
      ? await base.contextFromSession(
          snapshot,
          tenant === undefined ? {} : { tenant },
        )
      : base.contextFor(
          key.userId === null && key.shared === null && key.support === null
            ? { kind: "none", reason: "none" }
            : {
                kind: "invalid",
                reason: "token",
                error: dbError(
                  "unauthorized",
                  "No caller handed this remote cache key over: call the function through bsb.remote()",
                ),
              },
        );

    return { ctx, view: toSession(ctx.auth), scope: "remote", tenant };
  };

  const stageWarn = development
    ? (message: string): void => {
        betterSupabase.events.logger.warn(message);
      }
    : undefined;

  const applyEntry = (
    ctx: ServerContext<M, F, E, C, P, B>,
    view: AuthSession<C, P>,
    scope: CacheScope,
    tenant: string | undefined,
    entry: CachedOptions,
  ): void => {
    applyCacheEntry({
      ctx,
      view,
      scope,
      tenant,
      entry: withReadSetTables(entry),
      userTags,
      warn: development
        ? (message) => {
            betterSupabase.events.logger.warn(message);
          }
        : undefined,
    });
  };

  /** The bootstrap calls of one request, by session key, schema, rpc and args. */
  const bootstrapCalls = cache(() => new Map<string, Promise<BootstrapRow>>());

  const next: BetterNext<M, F, E, C, P, PermissionRef<A>, B, V> = extendServer<
    BetterNext<M, F, E, C, P, PermissionRef<A>, B, V>
  >(withAccounts, {
    claims,
    getClaims,
    refreshSessionCache: async () =>
      refreshCallerCache(await getClaims(), base),

    async cached(cachedOptions = {}) {
      await awaitStage(cachedOptions.stage, stageWarn);

      const { ctx, view, scope, tenant } = await scopeOf(cachedOptions);
      applyEntry(ctx, view, scope, tenant, cachedOptions);

      return withExtra(ctx, { session: view });
    },

    async user() {
      const { ctx, view, scope, tenant } = await scopeOf({});
      applyEntry(ctx, view, scope, tenant, { life: { stale: 300 } });

      return gateUserOf(view, tenant);
    },

    async sessionHandle(handleOptions = {}) {
      const ctx = await current(handleOptions.tenant);
      const view = toSession(ctx.auth);
      // A support session's restrictions live in its context, which a scope
      // can't rebuild from a handle: it reads the request's own.
      const snapshot = ctx.support ? null : snapshotOf(ctx.auth);

      const handle = cacheKeyOf({
        userId: view.kind === "user" ? view.user.id : null,
        tenant: tenantFor(ctx, view),
        support: ctx.support?.session.id ?? null,
        snapshot,
        share: "session",
      });

      parkUntilResponseEnds(handle, snapshot);

      return handle;
    },

    remote(fn, remoteOptions = {}) {
      return async (...args) => {
        const ctx = await current(remoteOptions.tenant?.(...args));
        const view = toSession(ctx.auth);
        // A support session's restrictions live in its context, which a remote
        // scope can't rebuild: its calls get no token.
        const snapshot = ctx.support ? null : snapshotOf(ctx.auth);

        const key = cacheKeyOf({
          userId: view.kind === "user" ? view.user.id : null,
          tenant: tenantFor(ctx, view),
          support: ctx.support?.session.id ?? null,
          snapshot,
          share: remoteOptions.share ?? "session",
        });

        const release = snapshot ? handOff(key, snapshot) : undefined;

        try {
          return await fn(key, ...args);
        } finally {
          release?.();
        }
      };
    },

    async bootstrap<T, S extends ReadSet = ReadSet>(
      bootstrapOptions: BootstrapOptions<Extract<keyof M, string>, S>,
    ): Promise<Bootstrap<C, P, T, ReadSetResult<S>>> {
      await awaitStage(bootstrapOptions.stage, stageWarn);

      const { ctx, view, scope, tenant } = await scopeOf(bootstrapOptions);
      const calls = bootstrapCalls();

      const result = await bootstrapWith<C, P, T, S>(
        {
          schema: (call) => bootstrapSchema(call, options, betterSupabase),
          evictSession,
          versions: base.versions,
          onEnded: (token, reason) => {
            markSessionEnded(
              token,
              reason === "user_banned" ? "banned" : "ended",
            );
          },
        },
        ctx,
        bootstrapOptions,
        tenant,
        mapBootstrapMemo(calls),
      );

      if (result.session.kind === "user" && !result.sessionActive) {
        cacheLife({ stale: 0, revalidate: 0, expire: 0 });

        if (bootstrapOptions.redirect !== undefined) {
          const reason =
            result.endReason === "user_banned"
              ? (bootstrapOptions.reasons?.banned ?? "user_banned")
              : (bootstrapOptions.reasons?.ended ?? "session_not_found");

          redirect(
            `${bootstrapOptions.redirect}?reason=${encodeURIComponent(reason)}`,
          );
        }

        return result;
      }

      const recorded =
        betterSupabase.meta.bootstrap?.tables?.[bootstrapOptions.rpc] ?? [];

      applyEntry(ctx, view, scope, result.tenant ?? undefined, {
        ...bootstrapOptions,
        tables: [...new Set([...(bootstrapOptions.tables ?? []), ...recorded])],
      });

      return result;
    },

    async getAccess(source, accessOptions = {}) {
      const boot = source && "session" in source ? source : undefined;
      const tenant = boot?.tenant ?? undefined;

      const snapshot = isSessionSnapshot(source)
        ? source
        : accessOptions.key
          ? (takeHandoff<C>(accessOptions.key) ?? null)
          : await getClaims();

      const ctx = await base.contextFromSession(
        snapshot,
        tenant === undefined ? {} : { tenant },
      );

      return accessOf<ServerContext<M, F, E, C, P, B>, C, P, PermissionRef<A>>(
        ctx,
        {
          tenant: tenant ?? tenantFor(ctx, toSession(ctx.auth)) ?? null,
          authzVersion: boot
            ? boot.authzVersion
            : (snapshot?.authzVersion ?? null),
          authorizer: base.authorizer,
        },
      );
    },

    locale: () => rootParam(options.rootParams?.locale),
    brand: () => rootParam(options.rootParams?.brand),
    tenant: () => rootParam(options.rootParams?.tenant),

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

    proxy: proxyHandler<C, P>({
      base,
      logger: betterSupabase.events.logger,
      collector,
      statsHeader,
      statsRoute,
      flushAfter,
    }),

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

      // SAFETY: `result` keeps the data type.
      const mapped = (o: Out): Out => (actionOptions.result?.(o) ?? o) as Out;

      return async (...args: unknown[]) => {
        const input = args.at(-1);
        const boundArgs = actionOptions.bound ? args.slice(0, -1) : [];

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
          return mapped({ ok: false, data: null, error: denied });
        }

        const checkedBound = await validateBound(
          actionOptions.bound,
          boundArgs,
        );

        if (!checkedBound.ok) {
          return mapped({ ok: false, data: null, error: checkedBound.error });
        }

        const bound = checkedBound.data;

        let parsed: unknown =
          input instanceof FormData ? formDataObject(input) : input;

        if (actionOptions.input) {
          const checked = await validate(actionOptions.input, parsed, "input");

          if (!checked.ok) {
            return mapped({ ok: false, data: null, error: checked.error });
          }

          parsed = checked.data;
        }

        // SAFETY: parsed is the validated input, or the raw input when the
        // action has no schema.
        const tenant = actionOptions.tenant?.(parsed as never, bound as never);

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
          return mapped({ ok: false, data: null, error: caller });
        }

        const refused = await actionOptions.guard?.(tenant, ctx);

        if (refused) {
          return mapped({ ok: false, data: null, error: refused });
        }

        const scope = ctx;
        let settled: Settled;

        try {
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema; requireTenant refused a missing tenant.
          settled = await settle(() =>
            fn(
              parsed as never,
              withExtra(scope, caller) as never,
              bound as never,
            ),
          );
        } finally {
          // Also when redirect() or notFound() follows a write.
          flushAfter();
          await writeCookies(ctx);
          await logActionStats(
            options.debug?.enabled ? collector : undefined,
            betterSupabase.events.logger,
            incomingRequest,
            statsHeader,
          );
        }

        // SAFETY: Out is the Result of the action's return type, which both branches build.
        return mapped(
          (settled.ok
            ? { ok: true, data: settled.data, error: null }
            : { ok: false, data: null, error: settled.error }) as Out,
        );
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
        invalidateAll(userTags(resolution.auth.user.id));
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
          ? userTags(resolution.auth.user.id)
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
        ? Object.values(target.specs).filter((spec) => isQuerySpec(spec))
        : isList(target)
          ? target
          : [target];

      const tags = new Set<string>();

      for (const table of isReadSet(target) ? readSetTables(target) : []) {
        for (const tag of tableTags(table, tagOptions)) {
          tags.add(tag);
        }
      }

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

    blockAction: (client, method, blockOptions) =>
      // SAFETY: blockActionOf calls `host.action` with the options and callback it was given.
      blockActionOf(
        next as never,
        invalidateAll,
        client as never,
        method,
        blockOptions as never,
      ),

    withContext: (factory) =>
      withContextFactory(next, factory, (ctx) => toSession(ctx.auth)),

    record: (type) => recordServer(next, type),

    recordAt: (type, id) => recordAtServer(next, type, id),
  });

  // SAFETY: the contexts differ only in `supabase`, which the server builds as SupabaseClient<D>
  // from the same BetterSupabase<…, D>; its untyped default is the same client.
  return next as BetterNext<M, F, E, C, P, PermissionRef<A>, B, V, D>;
}
