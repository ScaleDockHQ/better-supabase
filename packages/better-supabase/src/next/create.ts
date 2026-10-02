import type { StandardSchemaV1 } from "@standard-schema/spec";

import { cacheLife, cacheTag, revalidateTag, updateTag } from "next/cache.js";
import { cookies, headers } from "next/headers.js";
import { type NextRequest, NextResponse } from "next/server.js";
import { cache } from "react";

import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { CountRunner, LiveCountSeed } from "../realtime/live.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { type Aal, checkAal } from "../auth/mfa.ts";
import { toSession } from "../auth/view.ts";
import { dbError } from "../core/errors.ts";
import { isList } from "../core/guards.ts";
import { problemResponse } from "../core/problem.ts";
import { isReadSet, type ReadSet } from "../core/read-set.ts";
import { validate } from "../core/standard.ts";
import { EMPTY_STATS } from "../core/stats.ts";
import {
  DEFAULT_PIN_MS,
  PRIMARY_COOKIE,
  primaryCookie,
} from "../server/replicas.ts";
import {
  defaultExpose,
  guard,
  type GuardOptions,
  respond,
  settle,
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
  /** Where `next.debugRoute()` is mounted. Defaults to `/api/bs-stats`. */
  readonly route?: string;
}

/** Response header with the URL of the request's totals on `next.debugRoute()`. */
export const STATS_URL_HEADER = "x-bs-stats";

export interface ProxyOptions<C = unknown, U = unknown> {
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
    auth: AuthState<C, U>,
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
  /** Post-processes the final response; return a new one to replace it. */
  readonly after?: (
    response: Response,
    auth: AuthState<C, U>,
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
}

type ActionInput<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<S> | FormData
  : unknown;
type ActionParsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : unknown;
type Unwrapped<T> = T extends
  | { readonly ok: true; readonly data: infer D }
  | { readonly ok: false }
  ? D
  : T;

export interface BetterNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  U = unknown,
> extends BetterServer<M, F, E, C, U> {
  /** `proxy.ts`: refreshes sessions for page loads and server actions. */
  proxy(request: NextRequest, options?: ProxyOptions<C, U>): Promise<Response>;
  /** Server Components and actions: the caller's context, memoized per request. */
  server(): Promise<ServerContext<M, F, E, C, U>>;
  /**
   * The verified caller as serializable data (no token, no clients), memoized
   * per request. Wrap it in a `'use cache: private'` function with Cache
   * Components and pass the promise to `<SessionProvider>`.
   */
  session(): Promise<AuthSession<C, U>>;
  /**
   * The context for a session and its token, without reading the request.
   * The token is verified again (memoized, no network call); a token for
   * another user than `session` gives an `invalid` context.
   */
  serverFor(
    session: AuthSession<C, U>,
    options: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, U>>;
  /**
   * First statement of an app-authored `'use cache: private'` function: sets
   * `cacheLife` from the session's expiry (`sessionStale`, capped by
   * `life.stale`), tags the entry `bs:session:<user id>` plus `tags`, and
   * returns the caller's context plus `session`.
   *
   * ```ts
   * async function getCustomers() {
   *   'use cache: private';
   *   const { db } = await next.cached();
   *   return db.customers.findMany().orThrow();
   * }
   * ```
   */
  cached(options?: CachedOptions): Promise<CachedContext<M, F, E, C, U>>;
  /**
   * Drops every `next.cached()` entry of a user, e.g. after a role change,
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
   * (from `next.cached()`); otherwise it uses `next.server()`. A failed
   * count gives `count: null` instead of throwing.
   */
  liveCount<T extends Extract<keyof M, string>>(
    spec: QuerySpec<T, "count", number>,
    db?: CountRunner,
  ): Promise<LiveCountSeed<T>>;
  /** Route handler with auth, Result unwrapping and Problem Details errors. */
  route<P = Record<string, string | string[]>>(
    handler: (
      request: NextRequest,
      ctx: ServerContext<M, F, E, C, U> & { readonly params: P },
    ) => unknown,
    options?: GuardOptions,
  ): (
    request: NextRequest,
    segment: { readonly params: Promise<P> },
  ) => Promise<Response>;
  /** Server action returning a serializable `ActionResult`. */
  action<S extends StandardSchemaV1 | undefined, T>(
    options: ActionOptions<S>,
    fn: (
      input: ActionParsed<S>,
      ctx: ServerContext<M, F, E, C, U>,
    ) => Promise<T> | T,
  ): (input: ActionInput<S>) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
  /** Tags the current `"use cache"` scope with a table (and row) tag. */
  cacheTag(table: Extract<keyof M, string>, id?: string | number): void;
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
  ): void;
  /**
   * GET handler serving a request's database totals (`?id=<request id>`) for
   * `expectDbBudget`. Answers 404 unless `debug` is on.
   */
  debugRoute(): (request: Request) => Promise<Response>;
}

export interface SessionStaleOptions {
  /** Below this, the result would not be prefetched anyway. Defaults to 30. */
  readonly min?: number;
  /** 300 (5 minutes) joins the route's App Shell. Defaults to 300. */
  readonly max?: number;
}

/**
 * `cacheLife` `stale` seconds for a view of `session`: `max`, but never past
 * the token's expiry, and at least `min`.
 */
export function sessionStale(
  session: AuthSession,
  options: SessionStaleOptions = {},
  now: number = Date.now(),
): number {
  const min = options.min ?? 30;
  const max = options.max ?? 300;
  if (session.kind !== "user" || session.expiresAt === null) return max;
  const remaining = session.expiresAt - Math.floor(now / 1000);
  return Math.min(max, Math.max(min, remaining));
}

export interface CachedOptions {
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
  /** More `cacheTag`s for the entry, e.g. `snapshotTag(sub)` or `org:<id>`. */
  readonly tags?: readonly string[];
}

export type CachedContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  U = unknown,
> = ServerContext<M, F, E, C, U> & { readonly session: AuthSession<C, U> };

/** The tag `next.cached()` puts on a user's entries. */
export function sessionTag(userId: string): string {
  return `bs:session:${userId}`;
}

/** `bs:<table>` or `bs:<table>:<id>`. Mutations invalidate both. */
export function tagFor(table: string, id?: string | number): string {
  return id === undefined ? `bs:${table}` : `bs:${table}:${String(id)}`;
}

function invalidate(tag: string): void {
  try {
    updateTag(tag);
  } catch {
    try {
      revalidateTag(tag, "max");
    } catch {
      // Outside a Next.js request (jobs, scripts): nothing to invalidate.
    }
  }
}

/**
 * Invalidates `bs:<table>` for every table in the target and
 * `bs:<table>:<id>` for the changed rows. `createNext` attaches it unless
 * `cacheTags: false`.
 */
export function nextCache(): CacheAdapter {
  return {
    name: "next",
    invalidate: (target) => {
      for (const table of target.tables) invalidate(tagFor(table));
      for (const id of target.ids) invalidate(tagFor(target.table, id));
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
 * next.proxy(request, {
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

/** Page loads, client navigations and server actions; never prefetches or assets. */
export function shouldRefresh(request: Request): boolean {
  const h = request.headers;
  if (request.method !== "GET" && request.method !== "HEAD")
    return h.has("next-action");
  if (
    h.has("next-router-prefetch") ||
    h.get("purpose") === "prefetch" ||
    h.get("sec-purpose")?.includes("prefetch")
  ) {
    return false;
  }
  if (h.get("rsc") === "1") return true;
  const dest = h.get("sec-fetch-dest");
  if (dest) return dest === "document";
  return h.get("accept")?.includes("text/html") ?? false;
}

/**
 * The Next.js adapter: proxy, Server Components, route handlers, server
 * actions and cache tags, on top of `createServer`.
 *
 * ```ts
 * export const next = createNext(sb);
 * ```
 */
export function createNext<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  U = unknown,
>(
  sb: BetterSupabase<M, D, F, E, C, U>,
  options: NextOptions = {},
): BetterNext<M, F, E, C, U> {
  const base = createServer(sb, options);
  const pinMs = options.replicas?.pinMs ?? DEFAULT_PIN_MS;
  const expose = options.exposeErrors ?? defaultExpose();

  if (options.cacheTags !== false) sb.cache(nextCache());

  const debug = options.debug;
  const statsHeader = debug?.header ?? "x-bs-db-calls";
  const statsRoute = debug?.route ?? "/api/bs-stats";
  const development = process.env["NODE_ENV"] === "development";
  const collector = debug?.enabled
    ? sharedCollector({
        logger: sb.events.logger,
        warn: development,
        ...(debug.budget ? { budget: debug.budget } : {}),
      })
    : undefined;
  const statsFor = (request: Request): ContextOptions => {
    const id = collector && request.headers.get(REQUEST_ID_HEADER);
    return id ? { stats: collector.recorderFor(id) } : {};
  };

  const incomingRequest = async (): Promise<Request> =>
    new Request("http://next.local/", {
      headers: new Headers(await headers()),
    });

  const server = cache(async (): Promise<ServerContext<M, F, E, C, U>> => {
    const request = await incomingRequest();
    return base.context(request, statsFor(request));
  });

  const session = cache(async (): Promise<AuthSession<C, U>> => {
    const resolution = await base.resolve(await incomingRequest(), {
      refresh: false,
    });
    return toSession(resolution.auth);
  });

  const serverFor = async (
    view: AuthSession<C, U>,
    { token }: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, U>> => {
    const request = new Request("http://next.local/", {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    });
    const ctx = await base.context(request);
    const matches =
      ctx.auth.kind === "user"
        ? view.kind === "user" && view.user.id === ctx.auth.user.id
        : view.kind !== "user";
    if (matches) return ctx;
    return base.contextFor({
      kind: "invalid",
      reason: "token",
      error: dbError(
        "unauthorized",
        "The token does not belong to the session passed to serverFor()",
      ),
    });
  };

  const withAccounts = withExtra(base, {
    deleteAccount: ((userId, deleteOptions) =>
      base.deleteAccount(userId, deleteOptions).map((result) => {
        invalidate(sessionTag(userId));
        return result;
      })) satisfies BetterServer<M, F, E, C, U>["deleteAccount"],
  });

  return extendServer<BetterNext<M, F, E, C, U>>(withAccounts, {
    server,
    session,
    serverFor,

    async cached(cachedOptions = {}) {
      const [view, ctx] = await Promise.all([session(), server()]);
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
        ...(cachedOptions.tags ?? []),
      ];
      if (tags.length > 0) cacheTag(...tags);
      return withExtra(ctx, { session: view });
    },

    invalidateSession(userId, invalidateOptions = {}) {
      invalidate(sessionTag(userId));
      for (const tag of invalidateOptions.tags ?? []) invalidate(tag);
    },

    async liveCount(spec, db) {
      const runner = db ?? (await server()).db;
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
      const custom = await proxyOptions.protect?.(resolution.auth, request);
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
        const ctx = await base.context(request, statsFor(request));
        const denied = guard(
          ctx.auth,
          guardOptions.allow,
          guardOptions.aal,
          guardOptions.scopes,
        );
        const instance = request.nextUrl.pathname;
        if (denied) return problemResponse(denied, { instance, expose });
        const params = await segment.params;
        const response = await respond(
          () => handler(request, withExtra(ctx, { params })),
          { instance, expose },
        );
        if (ctx.replica?.wrote) {
          try {
            response.headers.append("set-cookie", primaryCookie(pinMs));
          } catch {
            // A handler returned a Response with immutable headers.
          }
        }
        if (collector) {
          try {
            response.headers.set(statsHeader, formatStats(ctx.stats()));
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
        const ctx = await server();
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
        const settled = await settle(() => fn(parsed as never, ctx));
        if (ctx.replica?.wrote) {
          (await cookies()).set(PRIMARY_COOKIE, String(Date.now() + pinMs), {
            path: "/",
            maxAge: Math.max(1, Math.ceil(pinMs / 1000)),
            httpOnly: true,
            sameSite: "lax",
          });
        }
        // SAFETY: Out is the Result of the action's return type, which both branches build.
        return (
          settled.ok
            ? { ok: true, data: settled.data, error: null }
            : { ok: false, data: null, error: settled.error }
        ) as Out;
      };
    },

    cacheTag(table, id) {
      cacheTag(tagFor(table), ...(id === undefined ? [] : [tagFor(table, id)]));
    },

    cacheTags(target) {
      const specs = isReadSet(target)
        ? Object.values(target.specs)
        : isList(target)
          ? target
          : [target];
      const tags = new Set<string>();
      for (const spec of specs) {
        for (const table of sb.tablesOf(spec)) tags.add(tagFor(table));
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
