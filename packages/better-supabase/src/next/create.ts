import type { StandardSchemaV1 } from "@standard-schema/spec";

import {
  cacheLife,
  cacheTag,
  io,
  revalidateTag,
  updateTag,
} from "next/cache.js";
import { cookies, headers } from "next/headers.js";
import { after, type NextRequest, NextResponse } from "next/server.js";
import { cache } from "react";

import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { CountRunner, LiveCountSeed } from "../realtime/live.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { SupportStartRequest } from "../server/support.ts";

import { type Aal, checkAal } from "../auth/mfa.ts";
import { SUPPORT_COOKIE, supportCookieMaxAge } from "../auth/support-cookie.ts";
import { toSession } from "../auth/view.ts";
import { dbError } from "../core/errors.ts";
import { isList } from "../core/guards.ts";
import { problemResponse } from "../core/problem.ts";
import { isReadSet, type ReadSet } from "../core/read-set.ts";
import { validate } from "../core/standard.ts";
import { type DbStats, EMPTY_STATS } from "../core/stats.ts";
import { bearerRequest, flushEvents, handle } from "../server/adapter.ts";
import { serverCore } from "../server/entries/core.ts";
import {
  defaultExpose,
  guard,
  type GuardOptions,
  settle,
  type Settled,
} from "../server/respond.ts";
import {
  type BetterServer,
  type ContextOptions,
  createServer,
  extendServer,
  type ServerContext,
  type ServerOptions,
  withExtra,
} from "../server/server.ts";
import {
  type DbBudget,
  formatStats,
  REQUEST_ID_HEADER,
  sharedCollector,
} from "./collector.ts";
import {
  isRedirect,
  mutableResponse,
  overrideRequestHeaders,
  serverTimingValue,
} from "./proxy.ts";

export interface NextOptions extends ServerOptions {
  /** Invalidate `tagFor(table)` cache tags after mutations. Defaults to true. */
  readonly cacheTags?: boolean;
  /** Include internal error messages in Problem Details. Defaults to development only. */
  readonly exposeErrors?: boolean;
  /** Per-request database call counts. See the Budget docs. */
  readonly debug?: NextDebugOptions;
}

export interface NextDebugOptions {
  /** Collect outside development too, e.g. for e2e runs against `next start`. */
  readonly enabled?: boolean;
  /** Header with `calls;waves;ms` on route handler responses. Defaults to `x-bs-db-calls`. */
  readonly header?: string;
  /** Warns in development when one render goes over it. */
  readonly budget?: DbBudget;
  /** Where `bs.debugRoute()` is mounted. Defaults to `/api/bs-stats`. */
  readonly route?: string;
}

/** Response header with the URL of the request's totals on `bs.debugRoute()`. */
export const STATS_URL_HEADER = "x-bs-stats";

export interface ProxyOptions<C = unknown, P = unknown> {
  /**
   * Another middleware to compose with, such as next-intl's. It runs on the
   * original request, alongside auth; its rewrite, redirect or request
   * headers are kept, and refreshed cookies are merged into its response.
   */
  readonly before?: (
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
  /** Answer before rendering, e.g. redirect signed-out users. Refreshed cookies are kept. */
  readonly protect?: (
    auth: AuthState<C, P>,
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
  /**
   * A prefetch never refreshes, so a session cookie whose token expired
   * resolves to `{ kind: 'anon', reason: 'expired' }` there. `'protect'`
   * (the default) passes that to `protect` like any other caller.
   * `'render'` skips `protect` for it, so the prefetch renders signed out
   * instead of caching a redirect to sign-in; `sessionStale` keeps that view
   * out of the App Shell, and the navigation itself refreshes the session.
   */
  readonly expiredPrefetch?: "protect" | "render";
  /**
   * Methods that run `protect`. Defaults to `GET` and `HEAD`, so a Server
   * Action POST is not redirected before the action runs. Set `true` to
   * include mutations, or pass the methods yourself.
   */
  readonly protectMethods?: true | readonly string[];
  /** Post-processes the final response; return a new one to replace it. */
  readonly after?: (
    response: Response,
    auth: AuthState<C, P>,
  ) => Response | undefined | void | Promise<Response | undefined | void>;
  /**
   * Adds `Server-Timing: bs-proxy;dur=..., bs-verify;dur=...` (ms): the whole
   * proxy, and resolving the session (a local verify, or a refresh).
   */
  readonly serverTiming?: boolean;
}

export type ActionResult<T> =
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

export interface ActionOptions<
  S extends StandardSchemaV1 | undefined,
> extends GuardOptions {
  /** Validates the input (plain object or `FormData`) with any Standard Schema. */
  readonly input?: S;
  /**
   * The active tenant for the action's context, from the validated input,
   * instead of `NextOptions.tenant`. It is checked the same way: the
   * `tenant()` plugin and `current_tenant_id()` only honor a tenant the
   * caller belongs to.
   */
  readonly tenant?: (input: ActionParsed<S>) => string | undefined;
}

export interface ScopeOptions {
  /**
   * The active tenant, e.g. from route params, instead of `NextOptions.tenant`
   * (whose request has the incoming headers but no URL here). It goes where
   * the resolver's result goes, so it gets the same checks: the `tenant()`
   * plugin and `current_tenant_id()` only honor a tenant the caller belongs to.
   */
  readonly tenant?: string;
}

type ActionInput<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<S> | FormData
  : unknown;
type ActionParsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : unknown;
// Distributes over a `Result` union: the `Err` member adds nothing, so an
// action that returns `err(...)` on one path keeps the data type of the others.
type Unwrapped<T> = T extends { readonly ok: true; readonly data: infer D }
  ? D
  : T extends { readonly ok: false }
    ? never
    : T;

export interface BetterNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /** `proxy.ts`: refreshes sessions for page loads and server actions. */
  proxy(request: NextRequest, options?: ProxyOptions<C, P>): Promise<Response>;
  /**
   * The caller's context. Without a request (Server Components, actions) it
   * reads the incoming headers and is memoized per request and tenant.
   *
   * ```ts
   * const { db } = await bs.context({ tenant: organizationId });
   * ```
   */
  context(options?: ScopeOptions): Promise<ServerContext<M, F, E, C, P>>;
  context(
    request: Request | undefined,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P>>;
  /**
   * The verified caller as serializable data (no token, no clients), memoized
   * per request. Wrap it in a `'use cache: private'` function with Cache
   * Components and pass the promise to `<SessionProvider>`.
   */
  session(): Promise<AuthSession<C, P>>;
  /**
   * The context for a session and its token, without reading the request.
   * The token is verified again (memoized, no network call); a token for
   * another user than `session` gives an `invalid` context.
   */
  contextForSession(
    session: AuthSession<C, P>,
    options: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P>>;
  /**
   * First statement of an app-authored `'use cache: private'` function: sets
   * `cacheLife` from the session's expiry (`sessionStale`, capped by
   * `life.stale`), tags the entry `bs:session:<user id>` plus `tags`, and
   * returns the caller's context plus `session`.
   *
   * ```ts
   * async function getCustomers() {
   *   'use cache: private';
   *   const { db } = await bs.cached();
   *   return db.customers.findMany().orThrow();
   * }
   * ```
   */
  cached(options?: CachedOptions): Promise<CachedContext<M, F, E, C, P>>;
  /**
   * Drops every `bs.cached()` entry of a user, e.g. after a role change,
   * and the entries tagged with `tags` (such as PermDock's `snapshotTag(userId)`).
   */
  invalidateSession(
    userId: string,
    options?: { readonly tags?: readonly string[] },
  ): void;
  /**
   * Counts on the server and returns a serializable seed for
   * `useLiveCount(seed)`, so the badge renders with a number and the client
   * only refetches on changes. Pass `db` inside `'use cache: private'`
   * (from `bs.cached()`); otherwise it uses `bs.context()`. A failed
   * count gives `count: null` instead of throwing.
   */
  liveCount<T extends Extract<keyof M, string>>(
    spec: QuerySpec<T, "count", number>,
    db?: CountRunner,
  ): Promise<LiveCountSeed<T>>;
  /** Route handler with auth, Result unwrapping and Problem Details errors. */
  route<Params = Record<string, string | string[]>>(
    handler: (
      request: NextRequest,
      ctx: ServerContext<M, F, E, C, P> & { readonly params: Params },
    ) => unknown,
    options?: GuardOptions,
  ): (
    request: NextRequest,
    segment: { readonly params: Promise<Params> },
  ) => Promise<Response>;
  /** Server action returning a serializable `ActionResult`. */
  action<S extends StandardSchemaV1 | undefined, T>(
    options: ActionOptions<S>,
    fn: (
      input: ActionParsed<S>,
      ctx: ServerContext<M, F, E, C, P>,
    ) => Promise<T> | T,
  ): (input: ActionInput<S>) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
  /**
   * Tags the current `"use cache"` scope with a table (and row) tag. With a
   * `tenant`, mutations in other tenants leave the entry cached.
   */
  cacheTag(
    table: Extract<keyof M, string>,
    id?: string | number,
    options?: TagOptions,
  ): void;
  /**
   * Tags the current `"use cache"` scope with every table the specs (or a
   * read set) read, plus the row of each `findById`, so any mutation that
   * changes one revalidates it.
   */
  cacheTags(
    target:
      | QuerySpec<Extract<keyof M, string>>
      | readonly QuerySpec<Extract<keyof M, string>>[]
      | ReadSet,
    options?: TagOptions,
  ): void;
  /**
   * GET handler serving a request's database totals (`?id=<request id>`) for
   * `expectDbBudget`. Answers 404 unless `debug` is on.
   */
  debugRoute(): (request: Request) => Promise<Response>;
  /**
   * Starts a support session for the signed-in admin and sets its cookie,
   * so the admin's next requests render as the target. Call it from a
   * server action.
   */
  startSupport(
    request: SupportStartRequest,
  ): Promise<ActionResult<SupportStarted>>;
  /** Ends the admin's support session and clears its cookie. Call it from a server action. */
  stopSupport(): Promise<ActionResult<{ readonly ended: boolean }>>;
}

/** What `startSupport` returns: plain data, safe across the action boundary. */
export interface SupportStarted {
  readonly sessionId: string;
  readonly targetUserId: string;
  readonly readOnly: boolean;
  /** ISO 8601. */
  readonly expiresAt: string;
}

/** The tag `bs.cached()` adds to entries rendered in a support session. */
export function supportTag(sessionId: string): string {
  return `bs:support:${sessionId}`;
}

export interface SessionStaleOptions {
  /**
   * With fewer seconds left on the token, the view is not reused at all (0):
   * Next.js would not prefetch it anyway. Defaults to 30.
   */
  readonly min?: number;
  /** 300 (5 minutes) joins the route's App Shell. Defaults to 300. */
  readonly max?: number;
}

/**
 * `cacheLife` `stale` seconds for a view of `session`: `max`, but never past
 * the token's expiry, and 0 once fewer than `min` seconds are left. A
 * signed-out view that a refresh would change (an `expired` or
 * `refresh_failed` cookie, or an `invalid` token) is 0 as well, so it never
 * joins the App Shell.
 */
export function sessionStale(
  session: AuthSession,
  options: SessionStaleOptions = {},
  now: number = Date.now(),
): number {
  const min = options.min ?? 30;
  const max = options.max ?? 300;
  switch (session.kind) {
    case "invalid":
      return 0;
    case "anon":
      return session.reason === "expired" || session.reason === "refresh_failed"
        ? 0
        : max;
    case "service":
    case "apiKey":
      return max;
    case "user": {
      if (session.expiresAt === null) return max;
      const remaining = session.expiresAt - Math.floor(now / 1000);
      return remaining < min ? 0 : Math.min(max, remaining);
    }
    default: {
      const exhaustive: never = session;
      return exhaustive;
    }
  }
}

export interface CachedOptions extends ScopeOptions {
  /**
   * The active tenant, as for `bs.context({ tenant })`. Next.js keys the
   * private cache on your function's arguments, so take the tenant as an
   * argument and pass it through; never read it from anywhere else.
   */
  readonly tenant?: string;
  /**
   * `cacheLife` for the entry. `stale` is `sessionStale`, and never more than
   * `stale` when it is set: pass PermDock's `cacheLifeFor(snapshot)` so the
   * entry goes stale with the snapshot too.
   */
  readonly life?: SessionStaleOptions & {
    readonly stale?: number;
    readonly revalidate?: number;
    readonly expire?: number;
  };
  /** More `cacheTag`s for the entry, e.g. `snapshotTag(sub)` or `organization:<id>`. */
  readonly tags?: readonly string[];
}

export type CachedContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = ServerContext<M, F, E, C, P> & { readonly session: AuthSession<C, P> };

/** The tag `bs.cached()` puts on a user's entries. */
export function sessionTag(userId: string): string {
  return `bs:session:${userId}`;
}

export interface TagOptions {
  /** The tenant the read is scoped to; `"*"` is every tenant's reads. */
  readonly tenant?: string;
}

/**
 * `bs:<table>`, `bs:<table>:<id>`, or `bs:<table>@<tenant>` for a read
 * scoped to one tenant. Mutations invalidate the table tag, the tag of their
 * tenant (`bs:<table>@*` without one) and the tags of the changed rows.
 */
export function tagFor(
  table: string,
  id?: string | number,
  options: TagOptions = {},
): string {
  if (id !== undefined) return `bs:${table}:${String(id)}`;
  return options.tenant === undefined
    ? `bs:${table}`
    : `bs:${table}@${options.tenant}`;
}

/** The table tags of a read: the tenant's and every tenant's, or the table's. */
function tableTags(table: string, options: TagOptions): string[] {
  return options.tenant === undefined
    ? [tagFor(table)]
    : [
        tagFor(table, undefined, options),
        tagFor(table, undefined, { tenant: "*" }),
      ];
}

/** The second argument of `revalidateTag`: a `cacheLife` profile name or `{ expire }`. */
type RevalidateProfile = string | { readonly expire?: number };

/** The next read waits for fresh data instead of serving the stale entry. */
const EXPIRE_NOW = { expire: 0 } as const;

/**
 * Invalidates tags with `updateTag` (Server Actions), else `revalidateTag`
 * (Route Handlers), else not at all (jobs, scripts). The first tag decides
 * for the rest, so a mutation outside an action throws once, not per tag.
 */
function invalidateAll(
  tags: readonly string[],
  profile: RevalidateProfile = EXPIRE_NOW,
): void {
  let index = 0;
  try {
    for (; index < tags.length; index++) updateTag(tags[index]!);
    return;
  } catch {
    // Not in a Server Action: revalidate from the tag that failed.
  }
  try {
    for (; index < tags.length; index++) revalidateTag(tags[index]!, profile);
  } catch {
    // Outside a Next.js request (jobs, scripts): nothing to invalidate.
  }
}

export interface NextCacheOptions {
  /**
   * How a mutation outside a Server Action (a route handler, a webhook)
   * expires its tags with `revalidateTag`. Defaults to `{ expire: 0 }`, so
   * the next read waits for fresh data; `'max'` serves the stale entry
   * while it revalidates.
   */
  readonly revalidate?: string | { readonly expire?: number };
}

/**
 * Invalidates `bs:<table>` for every table in the target, the tenant's
 * `bs:<table>@<tenant>` (every tenant's `bs:<table>@*` when the mutation has
 * no tenant) and `bs:<table>:<id>` for the changed rows. Reads another tenant
 * tagged stay cached. `createNext` attaches it unless `cacheTags: false`.
 */
export function nextCache(options: NextCacheOptions = {}): CacheAdapter {
  return {
    name: "next",
    invalidate: (target) => {
      const tenant = { tenant: target.tenant ?? "*" };
      const tags: string[] = [];
      for (const table of target.tables)
        tags.push(tagFor(table), tagFor(table, undefined, tenant));
      for (const id of target.ids) tags.push(tagFor(target.table, id));
      invalidateAll(tags, options.revalidate);
    },
  };
}

function formDataObject(form: FormData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of new Set(form.keys())) {
    const values = form.getAll(key);
    out[key] = values.length > 1 ? values : values[0];
  }
  return out;
}

export interface RequireAalOptions {
  /**
   * Page that enrolls or challenges a second factor. Signed-in users below
   * the level are redirected there with `?next=<path>`; without it they get
   * a 403 Problem Details response.
   */
  readonly redirect?: string;
  /** Paths that need the level. Defaults to every path but `redirect`. */
  readonly match?: (pathname: string) => boolean;
}

/**
 * A `proxy` `protect` that keeps signed-in users below `level` out of the
 * matched paths. The JWT carries no factor list, so this also sends users
 * without a factor to `redirect` to enroll one. Anonymous callers pass;
 * combine it with your sign-in redirect.
 *
 * ```ts
 * bs.proxy(request, {
 *   protect: requireAal('aal2', { redirect: '/mfa', match: (path) => path.startsWith('/settings') }),
 * });
 * ```
 */
export function requireAal(
  level: Aal,
  options: RequireAalOptions = {},
): (auth: AuthState, request: NextRequest) => Response | undefined {
  return (auth, request) => {
    const { pathname, search } = request.nextUrl;
    if (options.redirect !== undefined && pathname === options.redirect) return;
    if (options.match && !options.match(pathname)) return;
    const denied = checkAal(auth, level);
    if (!denied) return;
    if (options.redirect === undefined) return problemResponse(denied);
    const target = new URL(options.redirect, request.url);
    target.searchParams.set("next", `${pathname}${search}`);
    return NextResponse.redirect(target);
  };
}

/** A router or browser prefetch, by its request headers. */
function isPrefetch(request: Request): boolean {
  const h = request.headers;
  return (
    h.has("next-router-prefetch") ||
    h.get("purpose") === "prefetch" ||
    (h.get("sec-purpose")?.includes("prefetch") ?? false)
  );
}

/** Page loads, client navigations and server actions; never prefetches or assets. */
export function shouldRefresh(request: Request): boolean {
  const h = request.headers;
  if (request.method !== "GET" && request.method !== "HEAD")
    return h.has("next-action");
  if (isPrefetch(request)) return false;
  if (h.get("rsc") === "1") return true;
  const dest = h.get("sec-fetch-dest");
  if (dest) return dest === "document";
  return h.get("accept")?.includes("text/html") ?? false;
}

/**
 * Event hubs that already invalidate Next.js cache tags. Every instance a
 * definition derives shares its hub, and `createNext` can run again for one
 * definition (hot reload, a definition in another package), so tags are
 * invalidated once per mutation.
 */
const nextCacheAttached = new WeakSet<object>();

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
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: NextOptions = {},
): BetterNext<M, F, E, C, P> {
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

  /** `null` runs `NextOptions.tenant`; a string is the caller's explicit tenant. */
  const scoped = cache(
    async (explicit: string | null): Promise<ServerContext<M, F, E, C, P>> => {
      const { request, resolution } = await incoming();
      const [tenant, support] = await Promise.all([
        explicit ?? options.tenant?.(request, resolution.auth),
        base.support.current(request, resolution.auth),
      ]);
      // Both tenants take the resolver's path, so they get the same checks.
      return core.context(
        resolution,
        request,
        { ...statsFor(request), ...(support ? { support } : {}) },
        tenant,
      );
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
  });

  return extendServer<BetterNext<M, F, E, C, P>>(withAccounts, {
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
        stale: life?.stale === undefined ? stale : Math.min(stale, life.stale),
        ...(life?.revalidate === undefined
          ? {}
          : { revalidate: life.revalidate }),
        ...(life?.expire === undefined ? {} : { expire: life.expire }),
      });
      const tags = [
        ...(view.kind === "user" ? [sessionTag(view.user.id)] : []),
        ...(ctx.support ? [supportTag(ctx.support.session.id)] : []),
        ...(cachedOptions.tags ?? []),
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
      };
    },

    async proxy(request, proxyOptions = {}) {
      const started = performance.now();
      const id = collector ? crypto.randomUUID() : undefined;
      let verifyMs = 0;
      // `before` (i18n rewrites, redirects) and auth run on the original request.
      const [early, resolution] = await Promise.all([
        proxyOptions.before?.(request),
        base
          .resolve(request, { refresh: shouldRefresh(request) })
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
      const custom =
        rendersSignedOut || !runsProtect
          ? undefined
          : await proxyOptions.protect?.(resolution.auth, request);
      const initial = custom ?? early;
      if (
        !initial &&
        resolution.cookies.length === 0 &&
        !id &&
        !proxyOptions.after &&
        !proxyOptions.serverTiming
      ) {
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
              const params = await segment.params;
              return handler(request, withExtra(ctx, { params }));
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
        let ctx = await current();
        const denied = guard(
          ctx.auth,
          actionOptions.allow,
          actionOptions.aal,
          actionOptions.scopes,
        );
        if (denied) return { ok: false, data: null, error: denied };
        let parsed: unknown =
          input instanceof FormData ? formDataObject(input) : input;
        if (actionOptions.input) {
          const checked = await validate(actionOptions.input, parsed, "input");
          if (!checked.ok)
            return { ok: false, data: null, error: checked.error };
          parsed = checked.data;
        }
        // SAFETY: parsed is the validated input, or the raw input when the
        // action has no schema.
        const tenant = actionOptions.tenant?.(parsed as never);
        if (tenant !== undefined) ctx = await current(tenant);
        let settled: Settled;
        try {
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema.
          settled = await settle(() => fn(parsed as never, ctx));
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
      jar.delete({ name: supportCookieName, path: supportCookieOptions.path });
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
  });
}

const NEXT_DIGESTS: ReadonlySet<string> = new Set([
  "NEXT_REDIRECT",
  "NEXT_HTTP_ERROR_FALLBACK",
  "DYNAMIC_SERVER_USAGE",
  "BAILOUT_TO_CLIENT_SIDE_RENDERING",
  "HANGING_PROMISE_REJECTION",
  "NEXT_PRERENDER_INTERRUPTED",
]);
const REACT_POSTPONE = Symbol.for("react.postpone");

/**
 * `unstable_rethrow` without `next/navigation`: that entry loads the client
 * router context, which Turbopack can't resolve inside route handlers. The
 * digests are the ones Next 16 checks.
 */
function rethrowNextControlFlow(error: unknown): void {
  if (typeof error !== "object" || error === null) return;
  const digest = "digest" in error ? error.digest : undefined;
  if (
    (typeof digest === "string" &&
      NEXT_DIGESTS.has(digest.split(";", 1)[0] ?? "")) ||
    ("$$typeof" in error && error.$$typeof === REACT_POSTPONE) ||
    (error instanceof Error &&
      error.message.includes("needs to bail out of prerendering"))
  ) {
    // oxlint-disable-next-line typescript/only-throw-error -- React's postpone signal is not an Error, and Next needs the original value.
    throw error;
  }
  if ("cause" in error) rethrowNextControlFlow(error.cause);
}
