import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { UserClaims } from "@supabase/server";
import type { NextRequest } from "next/server.js";

import type { AuthState } from "../auth/resolve.ts";
import type { CookieScope } from "../auth/session.ts";
import type {
  AuthorizeUrlParams,
  OtpParams,
  SignOutScope,
} from "../auth/sign-in.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthSession } from "../auth/view.ts";
import type {
  BlockArgsOf,
  BlockDataOf,
  BlockMethodName,
} from "../blocks/block-method.ts";
import type { PermissionSet } from "../blocks/permissions/permissions-controller.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { DbError } from "../core/errors.ts";
import type { KeptSkip, KeptStore } from "../core/kept-cache.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { ReadSet, ReadSetResult } from "../core/read-set.ts";
import type { FunctionSpec, QuerySpec } from "../core/spec.ts";
import type { StatsPhase, StatsRecorder } from "../core/stats.ts";
import type { TagOptions } from "../core/tags.ts";
import type { CountRunner, LiveCountSeed } from "../realtime/live.ts";
import type { BindingName } from "../records/bindings.ts";
import type { RecordType, RecordTypeBlocks } from "../records/record-type.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  Access,
  Bootstrap,
  BootstrapCallOptions,
} from "../server/bootstrap.ts";
import type { AuthOutageHook } from "../server/entries/session.ts";
import type {
  ActionInput,
  ActionParsed,
  ActionResult,
  AuthorizeOptions,
  AuthorizedContext,
  ResourceLoaderContext,
  Unwrapped,
} from "../server/kit.ts";
import type { GuardOptions } from "../server/respond.ts";
import type {
  AdminDb,
  BetterServer,
  ContextOptions,
  ServerContext,
  ServerOptions,
  SharedServer,
} from "../server/server-types.ts";
import type { SupportStartRequest } from "../server/support.ts";
import type { DbBudget } from "./collector.ts";
import type { RecordAt, RecordServer } from "./record.ts";
import type { RESOURCES_HOST, ResourcesHost } from "./resources.ts";
import type { AUTH_FLOWS_HOST, AuthFlowDeps } from "./sign-in.ts";
import type { GateUser } from "./user.ts";

/**
 * App-wide settings of every `bsb.action` (ADR 1256). `Ex` is what `envelope`
 * adds to each outcome.
 */
export interface NextActions<Ex = unknown> {
  /**
   * Fields merged into every outcome, success or error, after the action's own
   * `result`: a translated `message`, `fieldErrors` or a `code`. The actions'
   * return type carries them as `ActionResult<O> & Ex`.
   */
  readonly envelope?: (outcome: ActionResult<unknown>) => Ex | Promise<Ex>;
  /**
   * Runs before each action's own `guard`, for rules every action shares (a
   * read-only support session, a suspended brand). Return an error to refuse.
   */
  readonly guard?: (
    tenant: string | undefined,
    ctx: Parameters<NonNullable<ActionOptions<undefined>["guard"]>>[1],
  ) => DbError | undefined | Promise<DbError | undefined>;
  /**
   * Turns what a handler returned into a settled outcome, for a result type the
   * library does not know (a `better-result` `Result`). Return `undefined` to
   * leave the value to the default handling.
   */
  readonly from?: (
    value: unknown,
  ) =>
    | { readonly ok: true; readonly data: unknown }
    | { readonly ok: false; readonly error: DbError }
    | undefined;
}

export interface NextOptions extends ServerOptions {
  /**
   * An existing server, such as the one `createHono` returned, so both
   * frameworks share one `createServer`. The server options are then ignored.
   */
  readonly server?: SharedServer;
  /** Invalidate `tagFor(table)` cache tags after mutations. Defaults to true. */
  readonly cacheTags?: boolean;
  /**
   * Include internal error messages in Problem Details. Defaults to development
   * only.
   */
  readonly exposeErrors?: boolean;
  /** Per-request database call counts. See the Budget docs. */
  readonly debug?: NextDebugOptions;
  /**
   * Cookie scopes (`domain`, `path`) earlier deploys wrote the session at.
   * `signOut` also expires the session cookie at each of them. Never list the
   * current scope.
   */
  readonly cookieScopes?: readonly CookieScope[];
  /**
   * The getters from `next/root-params`, for `bsb.locale()`, `bsb.brand()` and
   * `bsb.tenant()`. Without `tenant` in the options, the context takes the
   * tenant from `rootParams.tenant`.
   *
   * ```ts
   * import * as rootParams from "next/root-params";
   * export const bsb = createNext(betterSupabase, { rootParams });
   * ```
   */
  readonly rootParams?: NextRootParams;
  /**
   * How `bsb.tenant(ref)` and `bsb.activeTenant()` find the tenant record: `by`
   * is the kind a plain string ref is read as (default `id`), and `resolve` has
   * one function per kind. A resolver returns the record (it needs an `id`) or
   * `null` for an unknown tenant, which ends the render with `notFound()`.
   *
   * ```ts
   * createNext(betterSupabase, {
   *   rootParams,
   *   tenants: {
   *     by: "slug",
   *     resolve: { slug: (slug) => getOrganizationBySlug(slug) },
   *   },
   * });
   * ```
   */
  readonly tenants?: NextTenants;
  /**
   * The caller's keys in the active tenant from a source that costs no database
   * call, such as the token's `permissions` claim or the shell's bootstrap
   * entry. `bsb.record(...).get()` and `recordListServer` use it for their
   * `can` flags and call `my_permissions` only when it returns `undefined` or
   * `null`. The keys must be the full set: a set that omits a key the record
   * type checks denies it.
   */
  readonly heldPermissions?: () => Promise<PermissionSet | null | undefined>;
  /**
   * In development, warns when one render waits on more sequential database
   * round trips than this, and names the fix: load the page's data in one read
   * set. Defaults to 4; `false` turns the warning off. It needs the proxy,
   * which forwards the request id the totals are kept under.
   */
  readonly devRoundTripBudget?: number | false;
  /** Where `bsb.kept()` keeps its entries. */
  readonly kept?: NextKeptOptions;
}

export interface NextKeptOptions {
  /**
   * `vercelRuntimeCacheAdapter(getCache)`, `postgresKeptStore(...)` or your
   * own. Defaults to `memoryKeptStore()`, which each instance has on its own.
   */
  readonly store?: KeptStore;
  /** Called for each fill that was not stored, such as one over 2 MB. */
  readonly onSkip?: (skip: KeptSkip) => void;
  /**
   * Milliseconds a miss waits for the fill another instance holds the lease
   * for, before it fills itself. Only stores with `lease` coordinate instances.
   * Default: 250.
   */
  readonly wait?: number;
}

export interface NextDebugOptions {
  /** Collect outside development too, e.g. for e2e runs against `next start`. */
  readonly enabled?: boolean;
  /**
   * Header with `calls;waves;ms` on route handler responses. Defaults to
   * `x-bsb-db-calls`.
   */
  readonly header?: string;
  /** Warns in development when one render goes over it. */
  readonly budget?: DbBudget;
  /** Where `bsb.debugRoute()` is mounted. Defaults to `/api/bsb-stats`. */
  readonly route?: string;
  /**
   * Reports the process's first request: the time `better-supabase/next` took
   * to evaluate, when it was ready, and the first `createNext`, `warm()`,
   * `getClaims` and query. The stats header gets a `cold=` field while a step
   * is new, and the first query logs one `bsb.cold` line.
   */
  readonly coldStart?: boolean;
}

export interface ProxyOptions<C = unknown, P = unknown> {
  /**
   * Another middleware to compose with, such as next-intl's. It runs on the
   * original request, alongside auth; its rewrite, redirect or request headers
   * are kept, and refreshed cookies are merged into its response.
   */
  readonly before?: (
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
  /**
   * Answer before rendering, e.g. redirect signed-out users. Refreshed cookies
   * are kept.
   */
  readonly protect?: (
    auth: AuthState<C, P>,
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
  /**
   * Methods that run `protect`. Defaults to `GET` and `HEAD`, so a Server
   * Action POST is not redirected before the action runs. Set `true` to include
   * mutations, or pass the methods yourself.
   */
  readonly protectMethods?: true | readonly string[];
  /**
   * Post-processes the final response; return a new one to replace it. The
   * session cookies and cache headers are added to a replacement too. It also
   * receives the original request.
   */
  readonly after?: (
    response: Response,
    auth: AuthState<C, P>,
    request: NextRequest,
  ) => Response | undefined | void | Promise<Response | undefined | void>;
  /**
   * Adds `Server-Timing` entries in ms: `bsb-proxy` (the whole proxy),
   * `bsb-auth` (resolving the session), and `bsb-parse`, `bsb-verify`,
   * `bsb-refresh` and `bsb-ended` for the phases that ran.
   */
  readonly serverTiming?: boolean;
  /**
   * Refresh a session whose token expires within this many seconds. A token
   * outside the window is verified locally and never refreshed. Defaults to
   * `auth.leeway`, else 60.
   */
  readonly leeway?: number;
  /**
   * Ask Auth whether the session still exists (one network call), on top-level
   * document loads only. `true` checks every document load. `"bootstrap"` skips
   * the call: `bsb.bootstrap()` checks `session_active()` in the same query as
   * the page's data.
   */
  readonly verifySession?: true | "bootstrap" | VerifySessionOptions;
  /**
   * Called when a refresh failed because the Auth server was unreachable, timed
   * out or answered 5xx or 429. When the access token couldn't be kept
   * (`event.kept` is false), a returned `Response` replaces the proxy's
   * response, such as a 503 with `Retry-After`. A throw is logged and ignored.
   */
  readonly onAuthOutage?: AuthOutageHook;
}

export interface VerifySessionOptions {
  /**
   * The paths whose document loads check the session, such as `/settings`.
   * Defaults to every document load. Client navigations, prefetches and
   * mutations never check.
   */
  readonly paths?: readonly string[];
  readonly redirect?: string;
  /**
   * The `reason` query value on the redirect. Defaults to `session_not_found`
   * and `user_banned`.
   */
  readonly reasons?: { readonly ended?: string; readonly banned?: string };
}

/** A schema for the leading arguments of an action (`ActionOptions.bound`). */
export type BoundSchema = StandardSchemaV1<readonly unknown[]>;

/** The validated bound arguments, or an empty tuple without `bound`. */
export type BoundOutput<Bd> = Bd extends BoundSchema
  ? StandardSchemaV1.InferOutput<Bd>
  : readonly [];

/** The arguments of the returned action: bound ones first, then the input. */
export type BoundOptions<
  Bd,
  S extends StandardSchemaV1 | undefined,
> = Bd extends BoundSchema
  ? [...StandardSchemaV1.InferInput<Bd>, ActionInput<S>]
  : [input: ActionInput<S>];

/**
 * Turns the data of a successful action into the shape the caller gets, for
 * example a row into a view model. It runs after the cache tags in
 * `invalidates` are dropped; a thrown `DbException` becomes the action's
 * error.
 */
export type ActionMapper<D, O> = (data: D) => O | Promise<O>;

export interface ActionOptions<
  S extends StandardSchemaV1 | undefined,
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
  Bd extends BoundSchema | undefined = undefined,
>
  extends GuardOptions, AuthorizeOptions<ActionParsed<S>, C, P, R, Ref, X> {
  /** Validates the input (plain object or `FormData`) with any Standard Schema. */
  readonly input?: S;
  /**
   * The active tenant for the action's context, from the validated input,
   * instead of `NextOptions.tenant`. It is checked the same way: the
   * `membershipsExtension()` plugin and `current_tenant_id()` only honor a
   * tenant the caller belongs to.
   */
  readonly tenant?: (
    input: ActionParsed<S>,
    bound: BoundOutput<Bd>,
  ) => string | undefined;
  /**
   * A schema for the leading arguments an action takes through `.bind(null,
   * ...)`, for example `v.tuple([v.string()])` for a bound organization id.
   * They are validated before `tenant` runs, and `tenant(input, bound)` and the
   * action body (`fn(input, ctx, bound)`) read the validated tuple.
   */
  readonly bound?: Bd;
  /**
   * Runs after authentication and the permission check, before the action body.
   * Return an error to refuse the call; the body never runs. `tenant` is what
   * `tenant(input)` returned.
   */
  readonly guard?: (
    tenant: string | undefined,
    ctx: Pick<
      ServerContext<AnyModels, AnyFunctions, unknown, C, P>,
      "auth" | "resolution" | "supabase"
    >,
  ) => DbError | undefined | Promise<DbError | undefined>;
  /**
   * Maps the `ActionResult` before it returns, for example to translate errors
   * or to answer in the app's own shape. It may be async.
   */
  readonly result?: (
    outcome: ActionResult<unknown>,
  ) => ActionResult<unknown> | Promise<ActionResult<unknown>>;
  /**
   * Tables a successful call changes: drops the cache entries `bsb.tags` tagged
   * with them, such as `reads.deals.board.tables`.
   */
  readonly invalidates?: readonly string[];
  /**
   * Cache tags a successful call expires, computed from the tenant, the
   * validated input and the data the action returned. Declare a tag once as a
   * function of the tenant and use it here and in `bsb.tenant(..., { tags })`.
   */
  readonly tags?: (scope: {
    readonly tenant: string | undefined;
    readonly input: ActionParsed<S>;
    readonly data: unknown;
  }) => readonly string[];
  /**
   * Calls `refresh()` from `next/cache` after a successful call, so the client
   * router shows the write without each caller doing it.
   */
  readonly refresh?: boolean;
  /**
   * Drops every `bsb.cached()` entry of the caller after a successful call
   * (`bsb.evictSession`), which also re-renders the caller's page. Use it for a
   * write that changes what other domains read, such as a membership, role or
   * profile change; prefer `tags` when the write reaches one domain.
   */
  readonly evictSession?: boolean;
}

/**
 * How `blockAction` calls the method: without `args` it passes the validated
 * input as the only argument, so `args` is required when the method takes
 * anything else.
 */
export type BlockActionParams<S, A, Ctx> = [ActionParsed<S>] extends A
  ? { readonly args?: (input: ActionParsed<S>, ctx: Ctx) => A }
  : { readonly args: (input: ActionParsed<S>, ctx: Ctx) => A };

export interface RouteOptions<
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
>
  extends GuardOptions, AuthorizeOptions<NextRequest, C, P, R, Ref, X> {
  /**
   * Refresh an expired session cookie in the route and send the new cookies
   * with its response. For routes the proxy's matcher skips; off by default
   * because the proxy refreshes everything it matches.
   */
  readonly refresh?: boolean;
}

export interface RequireOptions<
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
>
  extends GuardOptions, AuthorizeOptions<undefined, C, P, R, Ref, X> {
  /** The active tenant, as for `bsb.context({ tenant })`. */
  readonly tenant?: string;
}

export interface ScopeOptions {
  /**
   * The active tenant, e.g. from route params, instead of `NextOptions.tenant`
   * (whose request has the incoming headers but no URL here). It goes where the
   * resolver's result goes, so it gets the same checks:
   * `membershipsExtension()` and `current_tenant_id()` only honor a tenant the
   * caller belongs to.
   */
  readonly tenant?: string;
}

/**
 * What `bsb.withContext(factory)` returns: `cached`, `getAccess` and `action`
 * with the factory's context merged in.
 */
export interface ContextualNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  Ref,
  B,
  D,
  X,
> {
  cached: (
    options?: CachedOptions<Extract<keyof M, string>>,
  ) => Promise<CachedContext<M, F, E, C, P, B, D> & X>;
  getAccess: (
    source?: Bootstrap<C, P> | SessionSnapshot<C> | null,
    options?: { readonly key?: RemoteCacheKey },
  ) => Promise<Access<ServerContext<M, F, E, C, P, B, D> & X, C, P, Ref>>;
  action: <
    S extends StandardSchemaV1 | undefined,
    T,
    R extends boolean = false,
    Bd extends BoundSchema | undefined = undefined,
    O = Unwrapped<Awaited<T>>,
  >(
    options: ActionOptions<S, C, P, R, Ref, NextResource<M, F, E, C, P, B>, Bd>,
    fn: (
      input: ActionParsed<S>,
      ctx: ServerContext<M, F, E, C, P, B, D> & AuthorizedContext<C, P, R> & X,
      bound: BoundOutput<Bd>,
    ) => Promise<T> | T,
    map?: ActionMapper<Unwrapped<Awaited<T>>, O>,
  ) => (...args: BoundOptions<Bd, S>) => Promise<ActionResult<O>>;
}

export interface BetterNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
  V extends AuthzVersionCache = AuthzVersionCache,
  // oxlint-disable-next-line typescript/no-explicit-any -- as ServerContext
  D = any,
  /** What `NextOptions.actions.envelope` adds to every action's outcome. */
  Ex = unknown,
> extends BetterServer<M, F, E, C, P, B, V> {
  /** `proxy.ts`: refreshes sessions for page loads and server actions. */
  proxy(request: NextRequest, options?: ProxyOptions<C, P>): Promise<Response>;
  /**
   * The caller's context. Without a request (Server Components, actions) it
   * reads the incoming headers and is memoized per request and tenant.
   *
   * ```ts
   * const { db } = await bsb.context({ tenant: organizationId });
   * ```
   */
  context(options?: ScopeOptions): Promise<ServerContext<M, F, E, C, P, B, D>>;
  context(
    request: Request | undefined,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B, D>>;
  /**
   * The verified caller as serializable data (no token, no clients), memoized
   * per request: the server-side counterpart of supabase-js `getClaims()`,
   * never of `getSession()`. Wrap it in a `'use cache: private'` function with
   * Cache Components and pass the promise to `<SessionProvider>`.
   */
  claims(): Promise<AuthSession<C, P>>;
  /**
   * The verified claims of the incoming request, shared by every cache scope of
   * the render: the first scope verifies the token and the others await that
   * verification, so ten `'use cache: private'` islands verify once. It awaits
   * `cookies()` before reading the clock, so it is safe in a private cache and
   * outside one. `null` for anyone but a signed-in user. Pass the snapshot to
   * `contextFromSession()` inside an island.
   *
   * ```tsx
   * async function Island() {
   *   "use cache: private";
   *   const session = await bsb.getClaims();
   *   const { db } = await bsb.contextFromSession(session);
   * }
   * ```
   */
  getClaims(): Promise<SessionSnapshot<C> | null>;
  /**
   * The context of a session snapshot from `getClaims()`, without reading the
   * request or verifying the token again. A snapshot this process didn't build
   * (one that crossed serialization or was built by hand) gets an `invalid`
   * context, so call `getClaims()` again in the scope that needs it.
   */
  contextFromSession(
    snapshot: SessionSnapshot<C> | null,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B, D>>;
  /**
   * First statement of an app-authored cache function: sets `cacheLife`
   * (`stale` 300 unless `life` says otherwise), tags the entry
   * `bsb:session:<user id>` and `bsb:session-id:<session id>` plus `tags`, and
   * returns the caller's context plus `session`. In `'use cache: private'` it
   * reads the request's session; in `'use cache: remote'` pass `{ scope:
   * "remote", key }` with the key `bsb.remote()` handed the function.
   *
   * ```ts
   * async function getCustomers() {
   *   "use cache: private";
   *   const { db } = await bsb.cached();
   *   return db.customers.list().orThrow();
   * }
   * ```
   */
  cached(
    options?: CachedOptions<Extract<keyof M, string>>,
  ): Promise<CachedContext<M, F, E, C, P, B, D>>;
  /**
   * First statement of a plain `"use cache"` function: sets `cacheLife` (the
   * shared defaults, `stale` 300, `revalidate` 300 and `expire` 3600, unless
   * `life` says otherwise), tags the entry with its `tables` and `id`, and
   * returns an anonymous context. Its reads run as the `anon` role, so row
   * level security decides what every visitor may see, instead of the service
   * role of `bsb.admin()`. It never reads the request, which `"use cache"`
   * forbids, so a signed-in caller gets the same rows as a visitor.
   *
   * ```ts
   * async function getPlans() {
   *   "use cache";
   *   const { db } = await bsb.public({ tables: ["plans"] });
   *   return db.plans.list().orThrow();
   * }
   * ```
   */
  public(
    options?: PublicCachedOptions<Extract<keyof M, string>>,
  ): Promise<CachedContext<M, F, E, C, P, B, D>>;
  /**
   * The signed-in user as plain data (`id`, `email`, `name`, `organizationId`),
   * never the token or the session, or `null` for anyone else. Call it inside a
   * `"use cache: private"` function: it sets `cacheLife({ stale: 300 })` and
   * the session tags like `bsb.cached()`, so the user rides in the App Shell.
   *
   * ```ts
   * export async function getUser() {
   *   "use cache: private";
   *   return bsb.user();
   * }
   * ```
   */
  user(): Promise<GateUser | null>;
  /**
   * Parks the request's verified session until the response is sent and returns
   * its serializable handle. Pass the handle to a `'use cache: private'`
   * function and to `bsb.cached({ session: handle })`: the scope resolves the
   * session from the handle, so it reads no cookie, header or token and runs no
   * verification. Without a handle (or after the response) the scope reads the
   * request's session as before. The handle names the user, session, tenant and
   * authorization version, never the token, so it is a sound cache key part.
   *
   * ```ts
   * const session = await bsb.sessionHandle();
   * <Customers session={session} />;
   *
   * async function Customers({ session }: { session: SessionHandle }) {
   *   "use cache: private";
   *   const { db } = await bsb.cached({ session });
   * }
   * ```
   */
  sessionHandle(options?: { readonly tenant?: string }): Promise<SessionHandle>;
  /**
   * Wraps a `'use cache: remote'` function so it can read as the caller: it
   * verifies the session outside the boundary (a memo hit), hands the token
   * over for the call, and passes the serializable key parts first. The token
   * is never a key part, so a rotation keeps the entry.
   *
   * ```ts
   * export const getReport = bsb.remote(async (key, year: number) => {
   *   "use cache: remote";
   *   const { db } = await bsb.cached({
   *     scope: "remote",
   *     key,
   *     tables: ["invoices"],
   *   });
   *   return db.invoices.list({ where: { year } }).orThrow();
   * });
   * ```
   */
  remote<A extends readonly unknown[], R>(
    fn: (key: RemoteCacheKey, ...args: A) => Promise<R>,
    options?: RemoteOptions<C, A>,
  ): (...args: A) => Promise<R>;
  /**
   * Keeps a read in a store across requests and deploys. The function runs as
   * the caller, under RLS; each user (with their tenant and authorization
   * version) has their own entry. A write to one of `tables` expires it, and a
   * stale entry is served while one call refreshes it. The value goes through
   * JSON. Inside `"use cache: private"` the entry's tags and life also apply to
   * the enclosing entry.
   *
   * ```ts
   * export const openInvoices = bsb.kept(
   *   (ctx, customerId: string) =>
   *     ctx.db.invoices.list({ where: { customerId, status: "open" } }),
   *   { name: "open-invoices", tables: ["invoices"] },
   * );
   * ```
   */
  kept<A extends readonly unknown[], R>(
    fn: (ctx: ServerContext<M, F, E, C, P, B, D>, ...args: A) => Promise<R>,
    options: KeptOptions<Extract<keyof M, string>, A>,
  ): KeptFunction<A, R>;
  /**
   * A fetch that counts each PostgREST, RPC, Storage and Edge Function call in
   * the current request's debug stats. Pass it to a Supabase client the app
   * builds itself, whose calls the request stats can't see otherwise. Without
   * `debug` it returns `fetch` unchanged; outside a request it sends the call
   * without recording it.
   *
   * ```ts
   * const client = createClient(url, key, {
   *   global: { fetch: bsb.statsFetch(fetch) },
   * });
   * ```
   */
  statsFetch(fetch?: typeof globalThis.fetch): typeof globalThis.fetch;
  /**
   * Expires `tags` in Next's cache (`updateTag` in a Server Action,
   * `revalidateTag` in a Route Handler) and in the kept store, and resolves
   * once the store has them, so another instance's next `bsb.kept()` read
   * misses. Use it where you wrote `updateTag` or `revalidateTag` next to a
   * `bsb.kept()` read: those calls alone leave the kept entry in place. Both
   * calls count in the request's `tagCalls` and `expiredTags`.
   *
   * @example
   *   await bsb.expireTags(["bsb:notes", `bsb:notes@${tenantId}`]);
   */
  expireTags(
    tags: readonly string[],
    options?: { readonly revalidate?: RevalidateProfile },
  ): Promise<void>;
  /**
   * Marks the database calls `run` starts as `phase` in the request's stats and
   * trace, so a wrapper (an authorization check, a write) shows its own share.
   * Calls in `bsb.action` are `action` unless a wrapper inside says otherwise.
   * Without debug it only runs `run`.
   *
   * @example
   *   const allowed = await bsb.phase("authorization", () =>
   *     can(user, "edit"),
   *   );
   */
  phase<T>(phase: StatsPhase, run: () => Promise<T>): Promise<T>;
  /**
   * One call for a page's user data: runs the sessions module's
   * `bootstrap_<rpc>` wrapper, which checks `session_active()` and returns the
   * caller's authorization version with the app function's data. Call it as the
   * first statement of a cache function, like `bsb.cached()`; React's `cache()`
   * runs the call once per request and key. A `false` `sessionActive` evicts
   * the user's entries and redirects to `redirect` when it is set.
   */
  bootstrap<T = unknown, S extends ReadSet = ReadSet>(
    options: BootstrapOptions<Extract<keyof M, string>, S> & {
      readonly require: "user";
    },
  ): Promise<UserBootstrap<C, P, T, ReadSetResult<S>>>;
  bootstrap<T = unknown, S extends ReadSet = ReadSet>(
    options: BootstrapOptions<Extract<keyof M, string>, S>,
  ): Promise<Bootstrap<C, P, T, ReadSetResult<S>>>;
  /**
   * The context, tenant and permission checks for a bootstrap result (or a
   * snapshot), bound to its authorization version, so islands stop rebuilding
   * their context one by one. In a remote scope pass the key.
   */
  getAccess(
    source?: Bootstrap<C, P> | SessionSnapshot<C> | null,
    options?: { readonly key?: RemoteCacheKey },
  ): Promise<Access<ServerContext<M, F, E, C, P, B, D>, C, P, Ref>>;
  /**
   * The same `cached()`, `getAccess()` and `action()`, handing back the app's
   * own context: `factory(session, base)` runs once per scope, from the session
   * the library already read, and its result merges into the context. The
   * factory may be async: each call awaits it, and concurrent calls share one
   * run.
   *
   * ```ts
   * export const app = bsb.withContext((session, base) => ({
   *   organizationId: base.tenant,
   *   isAdmin:
   *     session.kind === "user" && session.claims.app_role === "admin",
   * }));
   *
   * export const rename = app.action(
   *   { input: Rename },
   *   (input, ctx) => ctx.isAdmin,
   * );
   * ```
   */
  withContext<X extends object>(
    factory: (
      session: AuthSession<C, P>,
      base: ServerContext<M, F, E, C, P, B, D>,
    ) => Promise<X> | X,
  ): ContextualNext<M, F, E, C, P, Ref, B, D, X>;
  /** `rootParams.locale()`, or `undefined` without one or outside a render. */
  locale(): Promise<string | undefined>;
  /** `rootParams.brand()`, or `undefined` without one or outside a render. */
  brand(): Promise<string | undefined>;
  /**
   * Without arguments: `rootParams.tenant()`, or `undefined` without one or
   * outside a render.
   *
   * With a ref: the scope for a cached read, for a signed-in member of that
   * tenant. The ref is resolved through `NextOptions.tenants`, the caller's
   * membership and `permission` are checked, and a refusal ends the render with
   * `unauthorized()`, `notFound()` or `forbidden()` (ADR 1252), so the read has
   * no `null` ladder. `options` are those of `bsb.cached()`.
   *
   * ```ts
   * export const getAgendaItem = cache(async (org: string, id: string) => {
   *   "use cache: private";
   *   const { db } = await bsb.tenant(org, permissions.agenda.read, {
   *     tables: ["agenda_items"],
   *   });
   *   return await db.agendaItems.get(id).orNull();
   * });
   * ```
   */
  tenant(): Promise<string | undefined>;
  tenant(
    ref: TenantRef,
    permission?: Ref,
    options?: ScopeCallOptions<Extract<keyof M, string>>,
  ): Promise<TenantScope<M, F, E, C, P, B, D, Ref>>;
  /**
   * `bsb.tenant(ref, ...)` for the tenant `rootParams.tenant` names. Pass the
   * tenant as an argument of your cached function when the root param is not
   * readable there (a Server Action, a cache key).
   */
  activeTenant(
    permission?: Ref,
    options?: ScopeCallOptions<Extract<keyof M, string>>,
  ): Promise<TenantScope<M, F, E, C, P, B, D, Ref>>;
  /**
   * Checks the caller's membership and `permission` in the tenant `ref` names,
   * outside any cache, then returns `read(tenant)`. Make `read` a `"use cache"`
   * function of the tenant: reference data costs one database read per tenant
   * instead of one per user, and a caller who fails the check never reaches it.
   * A refusal ends the render like `bsb.tenant()` (ADR 1255).
   *
   * ```ts
   * async function readRoles(tenantId: string) {
   *   "use cache";
   *   cacheTag(`roles@${tenantId}`);
   *   return bsb.admin().roles.list({ where: { tenantId } }).orThrow();
   * }
   *
   * export const getRoles = (org: string) =>
   *   bsb.shared(org, permissions.roles.read, (t) => readRoles(t.id));
   * ```
   */
  shared<T>(
    ref: TenantRef,
    permission: Ref | undefined,
    read: (tenant: TenantRecord) => Promise<T>,
  ): Promise<T>;
  /**
   * The cached context for a signed-in caller without a tenant: `db`,
   * `session`, `user` and `can`. A caller without a session ends the render
   * with `unauthorized()`, one without `permission` with `forbidden()`.
   */
  auth(
    permission?: Ref,
    options?: ScopeCallOptions<Extract<keyof M, string>>,
  ): Promise<AuthScope<M, F, E, C, P, B, D, Ref>>;
  /**
   * `NextOptions.heldPermissions`, which record servers read before they ask
   * the database for the caller's keys.
   */
  readonly heldPermissions:
    | (() => Promise<PermissionSet | null | undefined>)
    | undefined;
  /**
   * Service-role repositories, like `bsb.admin()`. With `request` (the one a
   * route handler or proxy hook received) its calls count as admin calls in
   * that request's totals, so the dev budget and `expectDbBudget` see them.
   */
  admin(
    context?: RequestContext,
    options?: {
      readonly as?: string;
      readonly stats?: StatsRecorder;
      readonly request?: Request;
    },
  ): AdminDb<M, F, E, B>;
  /**
   * Drops every `bsb.cached()` entry of a user, e.g. after a role change, and
   * the entries tagged with `tags` (such as a permission snapshot's tag). In a
   * Server Action it also re-renders the caller's page, so no `refresh()` is
   * needed. It reaches server caches and the caller's router only: another
   * user's browser keeps its `'use cache: private'` entries until they go stale
   * or that user's token changes. It also evicts the user from the session memo
   * and the authorization version cache.
   */
  evictSession(
    userId: string,
    options?: { readonly tags?: readonly string[] },
  ): Promise<void>;
  /**
   * A Server Action for `<SessionProvider onAuthzChange>`: drops the caller's
   * own cached entries (the session and session id tags, plus the authorization
   * provider's `sessionTags`) after the browser refreshed its token, and evicts
   * them from the authorization version cache. Re-export it from a `"use
   * server"` file. A signed-out caller is a no-op.
   */
  refreshSessionCache(): Promise<void>;
  /**
   * Counts on the server and returns a serializable seed for
   * `useLiveCount(seed)`, so the badge renders with a number and the client
   * only refetches on changes. Pass `db` inside `'use cache: private'` (from
   * `bsb.cached()`); otherwise it uses `bsb.context()`. A failed count gives
   * `count: null` instead of throwing.
   */
  liveCount<T extends Extract<keyof M, string>>(
    spec: QuerySpec<T, "count", number>,
    db?: CountRunner,
  ): Promise<LiveCountSeed<T>>;
  /** Route handler with auth, Result unwrapping and Problem Details errors. */
  route<Params = Record<string, string | string[]>, R extends boolean = false>(
    handler: (
      request: NextRequest,
      ctx: ServerContext<M, F, E, C, P, B, D> &
        AuthorizedContext<C, P, R> & { readonly params: Params },
    ) => unknown,
    options?: RouteOptions<C, P, R, Ref, NextResource<M, F, E, C, P, B>>,
  ): (
    request: NextRequest,
    segment: { readonly params: Promise<Params> },
  ) => Promise<Response>;
  /**
   * Server action returning a serializable `ActionResult`.
   *
   * ```ts
   * export const invite = bsb.action(
   *   { input: Invite, requireTenant: true, roles: ["admin"] },
   *   async (input, { db, tenant }) =>
   *     db.invitations.create({ ...input, organizationId: tenant }),
   * );
   * ```
   */
  action<
    S extends StandardSchemaV1 | undefined,
    T,
    R extends boolean = false,
    Bd extends BoundSchema | undefined = undefined,
    O = Unwrapped<Awaited<T>>,
  >(
    options: ActionOptions<S, C, P, R, Ref, NextResource<M, F, E, C, P, B>, Bd>,
    fn: (
      input: ActionParsed<S>,
      ctx: ServerContext<M, F, E, C, P, B, D> & AuthorizedContext<C, P, R>,
      bound: BoundOutput<Bd>,
    ) => Promise<T> | T,
    map?: ActionMapper<Unwrapped<Awaited<T>>, O>,
  ): (...args: BoundOptions<Bd, S>) => Promise<ActionResult<O> & Ex>;
  /**
   * A server action that calls one block method as the caller, with the same
   * guard, validation and authorize checks as `action`. `map` shapes the data
   * it answers with, after `tags` saw the method's own data.
   *
   * ```ts
   * export const issueInvoice = bsb.blockAction(
   *   ({ db }) => db.invoices,
   *   "issue",
   *   {
   *     input: v.object({ invoiceId: v.pipe(v.string(), v.uuid()) }),
   *     permission: permissions.invoices.write,
   *     args: ({ invoiceId }) => [invoiceId],
   *   },
   *   (invoice) => ({ id: invoice.id }),
   * );
   * ```
   */
  // `K` stays unconstrained by `Cl`: checking a constraint that names `Cl`
  // fixes `Cl` before a destructuring `client` callback is inferred.
  blockAction<
    Cl extends object,
    const K extends string,
    S extends StandardSchemaV1 | undefined = undefined,
    R extends boolean = false,
    O = BlockDataOf<Cl, K & BlockMethodName<Cl>>,
  >(
    client: (ctx: ServerContext<M, F, E, C, P, B, D>) => Cl,
    method: K & BlockMethodName<Cl>,
    options: ActionOptions<S, C, P, R, Ref, NextResource<M, F, E, C, P, B>> &
      BlockActionParams<
        S,
        BlockArgsOf<Cl, K & BlockMethodName<Cl>>,
        ServerContext<M, F, E, C, P, B, D> & AuthorizedContext<C, P, R>
      >,
    map?: ActionMapper<BlockDataOf<Cl, K & BlockMethodName<Cl>>, O>,
  ): (input: ActionInput<S>) => Promise<ActionResult<O> & Ex>;
  /**
   * One record type's server binding (`defineRecordType`, which `gen` writes to
   * `records/<type>.ts`): `load` settles each block's binding for a record in a
   * Server Component, `actions` holds one Server Action per binding write, and
   * `tags` lists the record's cache tags. Each write drops the binding's and
   * the record's tags in the caller's organization.
   *
   * ```ts
   * const customer = bsb.record(customerRecord);
   * const { bindings, can } = await customer.get(id, {
   *   bindings: ["tags"],
   * });
   * ```
   */
  record<
    T extends string,
    RB extends RecordTypeBlocks,
    N extends BindingName<RB>,
  >(
    type: RecordType<T, RB> & { readonly bindings: readonly N[] },
  ): RecordServer<T, RB, N>;
  /**
   * One record's server verbs: `can`, `copyTo`, `trash` and `restore`. It is
   * named `recordAt` because `bsb.record` is the whole record type (ADR 0196).
   *
   * ```ts
   * const copied = await bsb.recordAt(customerRecord, id).copyTo(newId);
   * ```
   */
  recordAt<
    T extends string,
    RB extends RecordTypeBlocks,
    N extends BindingName<RB>,
  >(
    type: RecordType<T, RB> & { readonly bindings: readonly N[] },
    id: string,
  ): RecordAt<N>;
  /**
   * For Server Components: the caller's context, or the Next.js interrupt for a
   * refused caller. `unauthorized` calls `unauthorized()`, `forbidden` calls
   * `forbidden()` (both need `experimental.authInterrupts`, else `notFound()`),
   * and `not_found` calls `notFound()`.
   *
   * ```ts
   * const { db, tenant } = await bsb.require({
   *   requireTenant: true,
   *   roles: ["admin"],
   * });
   * ```
   */
  require<R extends boolean = false>(
    options?: RequireOptions<C, P, R, Ref, NextResource<M, F, E, C, P, B>>,
  ): Promise<ServerContext<M, F, E, C, P, B, D> & AuthorizedContext<C, P, R>>;
  /**
   * What `createResources(bsb)` from `better-supabase/next/resources` reads. It
   * is not an API of its own.
   */
  readonly [RESOURCES_HOST]: ResourcesHost<
    M,
    unknown,
    F,
    E,
    Ref,
    ServerContext<M, F, E, C, P, B, D>["db"]
  >;
  /**
   * Tags the current `"use cache"` scope with a table (and row) tag. With a
   * `tenant`, mutations in other tenants leave the entry cached.
   */
  tag(
    table: Extract<keyof M, string>,
    id?: string | number,
    options?: TagOptions,
  ): void;
  /**
   * Tags the current `"use cache"` scope with every table the specs (or a read
   * set) read, plus the row of each `get`, so any mutation that changes one
   * revalidates it.
   */
  tags(
    target:
      | QuerySpec<Extract<keyof M, string>>
      | readonly QuerySpec<Extract<keyof M, string>>[]
      | FunctionSpec
      | readonly (QuerySpec<Extract<keyof M, string>> | FunctionSpec)[]
      | ReadSet,
    options?: TagOptions,
  ): void;
  /**
   * GET handler serving a request's database totals (`?id=<request id>`) for
   * `expectDbBudget`. Answers 404 unless `debug` is on.
   */
  debugRoute(): (request: Request) => Promise<Response>;
  /**
   * Keeps `work` running after the response through Next's `after()`. Pass it
   * as a block's `kick.waitUntil`. Outside a request it logs a warning and the
   * work still runs.
   */
  waitUntil(work: Promise<unknown>): void;
  /**
   * Starts a support session for the signed-in admin and sets its cookie, so
   * the admin's next requests render as the target. Call it from a server
   * action.
   */
  startSupport(
    request: SupportStartRequest,
  ): Promise<ActionResult<SupportStarted>>;
  /**
   * Ends the admin's support session and clears its cookie. Call it from a
   * server action.
   */
  stopSupport(): Promise<ActionResult<{ readonly ended: boolean }>>;
  /**
   * What `createAuthFlows(bsb)` from `better-supabase/next/sign-in` reads. It
   * is not an API of its own.
   */
  readonly [AUTH_FLOWS_HOST]: AuthFlowDeps<C, P>;
}

export interface SignInCredentials {
  readonly email: string;
  readonly password: string;
  /** The `?next=` value from the sign-in URL; checked before use. */
  readonly next?: string | null;
}

export interface SignInOptions {
  /** Where to go when `next` is missing or not a same-origin path. */
  readonly fallback?: string;
}

/** `verifyOtp` input: a link's `token_hash`, or an email and its code. */
export type VerifyOtpParams = OtpParams & {
  /** Checked before use, like `signInWithPassword`'s. */
  readonly next?: string | null;
};

/** `signInWithOAuth` input. */
export interface SignInWithOAuthParams extends AuthorizeUrlParams {
  /** Where to go after the callback; checked before use. */
  readonly next?: string | null;
}

/** Where an email link lands. */
export interface EmailRedirect {
  /**
   * The absolute URL of the callback route that calls `exchangeCodeForSession`.
   * It must be in the project's redirect allow list.
   */
  readonly redirectTo: string;
  /** Rides on `redirectTo` as `?next=` when it is a same-origin path. */
  readonly next?: string | null;
}

/** `signInWithOtp` input. */
export interface SignInWithOtpParams extends EmailRedirect {
  readonly email: string;
  /** Create a user when no account has the email. Defaults to `true`. */
  readonly shouldCreateUser?: boolean;
  /** `user_metadata` for a user this creates. */
  readonly data?: Readonly<Record<string, unknown>>;
}

/** `resetPasswordForEmail` input. */
export interface ResetPasswordParams extends EmailRedirect {
  readonly email: string;
}

/** `signUp` input. */
export interface SignUpParams extends EmailRedirect {
  readonly email: string;
  readonly password: string;
  /** `user_metadata` for the new user. */
  readonly data?: Readonly<Record<string, unknown>>;
}

/** `resend` input. */
export interface ResendParams extends EmailRedirect {
  readonly type: "signup" | "email_change";
  readonly email: string;
}

/** `exchangeCodeForSession` input: the callback's `?code=` and `?next=`. */
export interface ExchangeCodeParams {
  readonly code: string;
  readonly next?: string | null;
}

/** `verifyMfa` input. */
export interface MfaVerification {
  readonly factorId: string;
  /** The code from the authenticator app. */
  readonly code: string;
  readonly next?: string | null;
}

/** `signOut` input. */
export interface SignOutParams {
  readonly scope?: SignOutScope;
  readonly next?: string | null;
}

/**
 * What the sign-in and sign-out helpers return: plain data, safe across the
 * action boundary. The committed session is on `getClaims()` and `context()`
 * for the rest of the request.
 */
export interface SignedIn {
  /** `next` when it is a same-origin path, else `fallback` (`/`). */
  readonly redirectTo: string;
  /**
   * The user has a verified MFA factor and the session is not `aal2` yet: send
   * them to the challenge (with `redirectTo` as its `next`) before
   * `redirectTo`. Advisory: keep the proxy and `action({ aal: 2 })` gates.
   */
  readonly mfa: boolean;
  /**
   * The signed-in user, read from the verified claims like `AuthSession.user`;
   * `null` once signed out.
   */
  readonly user: UserClaims | null;
}

/** What `startSupport` returns: plain data, safe across the action boundary. */
export interface SupportStarted {
  readonly sessionId: string;
  readonly targetUserId: string;
  readonly readOnly: boolean;
  /** ISO 8601. */
  readonly expiresAt: string;
}

/**
 * Where a `bsb.cached()` entry lives: `"use cache: private"` or `"use cache:
 * remote"`.
 */
export type CacheScope = "private" | "remote";

/**
 * The render stage a `bsb.cached()` or `bsb.bootstrap()` read waits for:
 * `"prefetch"` awaits `prefetch()` and `"navigation"` awaits `navigation()`
 * from `next/cache`, so the read leaves the App Shell and, for `"navigation"`,
 * the runtime prefetch too.
 */
export type CachedStage = "prefetch" | "navigation";

/** `cacheLife` for a `bsb.cached()` or `bsb.bootstrap()` entry. */
export interface CachedLife {
  /**
   * Seconds the client router reuses the entry. Defaults to 300, the shortest
   * time that keeps a private entry in the App Shell; the token's lifetime
   * doesn't cap it, since the proxy refreshes prefetches and sign-out evicts
   * the session tags. Below 300 the entry leaves the App Shell, below 30 the
   * prerender (development warns about both).
   */
  readonly stale?: number;
  /**
   * Defaults to 300 in the remote scope, and to the profile's in the private
   * one.
   */
  readonly revalidate?: number;
  /**
   * Defaults to 3600 in the remote scope, and to the profile's in the private
   * one.
   */
  readonly expire?: number;
  /**
   * Caps `stale` at the seconds left on the access token, and 0 once fewer than
   * 30 are left: the behavior before 0.35.
   */
  readonly capToToken?: boolean;
}

/**
 * Who shares a remote entry. `"session"` keys it on the Auth session, `"user"`
 * on the user across sessions. `{ key }` keys it on what the function returns
 * for the caller, such as a tenant and role fingerprint: that is the app's own
 * authorization decision, since every caller with the same key reads the
 * entry.
 */
export type CacheShare<C = unknown> =
  | "session"
  | "user"
  | { readonly key: (snapshot: SessionSnapshot<C> | null) => string };

/**
 * The serializable key parts `bsb.remote()` passes to a `"use cache: remote"`
 * function. They never hold the token; the function gets it through
 * `bsb.cached({ scope: "remote", key })`, from a handoff only the verified
 * caller's request filled.
 */
export interface RemoteCacheKey {
  readonly userId: string | null;
  readonly sessionId: string | null;
  readonly tenant: string | null;
  readonly authzVersion: number | null;
  /** The `{ key }` share's value. */
  readonly shared: string | null;
  /** The support session the caller acts in. */
  readonly support: string | null;
  /**
   * A hash of the generated schema meta, so an entry filled before a migration
   * and `gen` is not read after it, also when
   * `experimental.durableUseCacheEntries` keeps entries across deploys. `null`
   * without a generated schema.
   */
  readonly schema: string | null;
  /** The better-supabase version that filled the entry. */
  readonly library: string;
  /** The tables a `share: "tenant"` entry may read. */
  readonly tables?: readonly string[];
  /** The functions a `share: "tenant"` entry may call. */
  readonly functions?: readonly string[];
}

/** The serializable handle of a parked session; see `bsb.sessionHandle()`. */
export type SessionHandle = RemoteCacheKey;

export interface RemoteOptions<
  C = unknown,
  A extends readonly unknown[] = readonly unknown[],
> {
  /**
   * Defaults to `"session"`. `"tenant"` keys the entry on the tenant and the
   * grant the authorization provider's `shareKey` hook names, when every table
   * in `tables` is one the provider's `tables` shares per tenant, and the
   * remote scope's context then reads only `tables`, through the first caller's
   * own client under RLS. Otherwise it falls back to `"user"`.
   */
  readonly share?: CacheShare<C> | "tenant";
  /** The tables a `share: "tenant"` function reads. */
  readonly tables?: readonly string[];
  /** The functions it calls, as for `bsb.kept()`. */
  readonly functions?: readonly string[];
  /**
   * The active tenant from the function's arguments, as for `bsb.context({
   * tenant })`.
   */
  readonly tenant?: (...args: A) => string | undefined;
  /**
   * Names the function's entry records in request stats. Defaults to the
   * function's name, which a bundler may rename, then `"remote"`.
   */
  readonly name?: string;
}

export interface KeptOptions<
  T extends string = string,
  A extends readonly unknown[] = readonly unknown[],
> {
  /**
   * Names the function in the key and in reports. Required: a bundler may
   * rename the function, and two functions with one name share entries.
   */
  readonly name: string;
  /** Tables the function reads: a write to one expires the entry. */
  readonly tables?: readonly T[];
  /** A read set the function reads: its tables are added to `tables`. */
  readonly readSet?: ReadSet;
  /** More tags, or a function of the arguments that returns them. */
  readonly tags?: readonly string[] | ((...args: A) => readonly string[]);
  /**
   * Seconds the entry is fresh (`revalidate`, default 300) and kept, stale,
   * until a call refreshes it (`expire`, default 86400).
   */
  readonly life?: { readonly revalidate?: number; readonly expire?: number };
  /**
   * Part of the key. Change it when the function's result changes shape.
   * Defaults to a hash of the generated schema, so a migration starts new
   * entries; the build id is never part of the key.
   */
  readonly version?: string;
  /** The active tenant from the arguments, as for `bsb.remote()`. */
  readonly tenant?: (...args: A) => string | undefined;
  /**
   * Who shares an entry. `"user"` (the default) keys it on the user. `"tenant"`
   * keys it on the tenant and the grant the authorization provider's `shareKey`
   * hook names, when every table in `tables` is one the provider's `tables`
   * shares per tenant; the fill then reads only those tables, through the
   * caller's own client under RLS. Without the hook, a tenant or a sharable
   * table, the entry stays per user. `"public"` keeps one entry for every
   * visitor and fills it as the `anon` role, under RLS, without reading the
   * request: for data with no tenant, such as plans or currencies. The fill
   * reads only `tables`, and `tenant` is ignored.
   */
  readonly share?: "user" | "tenant" | "public";
  /**
   * Functions the function calls with `$rpc`, by database name. Each needs an
   * entry in the authorization provider's `sharedFunctions`: the tables it
   * reads are added to `tables`, and a `share: "tenant"` fill may call it.
   */
  readonly functions?: readonly string[];
}

/** What `bsb.kept()` returns. */
export interface KeptFunction<A extends readonly unknown[], R> {
  (...args: A): Promise<R>;
  /**
   * The same function for a session handle or the key `bsb.remote()` passed,
   * for a call inside a cache scope that can't read the request.
   */
  as(source: SessionHandle): (...args: A) => Promise<R>;
}

/**
 * Options of `bsb.cached({ keep })`: the reads of `ctx.db` are kept in the kept
 * store, so a cold page or a fresh instance answers them without calling the
 * database.
 */
export interface KeepReadsOptions<T extends string = string> {
  /**
   * Names the reads in the key and in reports. Required, as for `bsb.kept()`;
   * each table's reads add the table name.
   */
  readonly name: string;
  /**
   * Tables whose `db.$rpc()` reads are kept too, by tag. Without it a function
   * call goes to the database. Table reads need no declaration.
   */
  readonly tables?: readonly T[];
  /** As `KeptOptions.life`. */
  readonly life?: { readonly revalidate?: number; readonly expire?: number };
  /** As `KeptOptions.version`. */
  readonly version?: string;
}

interface CachedEntryOptions<T extends string = string> {
  /**
   * `cacheLife` for the entry. Pass a permission snapshot's lifetime as `stale`
   * so the entry goes stale with the snapshot too. `"max"` is `{ stale: 300,
   * revalidate: 2592000, expire: 31536000 }`, the profile of Next.js's
   * `cacheLife("max")`, for reads every write invalidates with `updateTag`; the
   * token cap of `capToToken` still applies.
   */
  readonly life?: CachedLife | "max";
  /**
   * Waits for a render stage before the entry's context resolves. It runs in
   * the calling component, never inside the `"use cache"` scope, where the
   * gates throw. Without Cache Components and Partial Prefetching it does
   * nothing and logs once in development.
   */
  readonly stage?: CachedStage;
  /** More tags for the entry, e.g. `snapshotTag(sub)` or `organization:<id>`. */
  readonly tags?: readonly string[];
  /**
   * Tables the entry reads, so the `updateTag` after a mutation drops it:
   * `bsb:<table>`, or with an active tenant `bsb:<table>@<tenant>` and
   * `bsb:<table>@*`, so other tenants' writes leave it cached.
   */
  readonly tables?: readonly T[];
  /**
   * A read set the entry reads (`reads.deals.board`): its tables are added to
   * `tables`. The `bsb:<table>` tags apply only to shared caches (`'use cache'`
   * and `'use cache: remote'`); a private cache is not invalidated by them.
   */
  readonly readSet?: ReadSet;
  /** With `tables`, also tags the row `bsb:<first table>:<id>`. */
  readonly id?: string | number;
}

export interface PrivateCachedOptions<T extends string = string>
  extends ScopeOptions, CachedEntryOptions<T> {
  /** Defaults to `"private"`. */
  readonly scope?: "private";
  /**
   * Keeps the reads of `ctx.db` in the kept store (`bsb.kept()`'s store), per
   * user, expired by writes to the table they read. Writes, `$many()` batches
   * and raw SQL always reach the database.
   */
  readonly keep?: KeepReadsOptions<T>;
  /**
   * The handle `bsb.sessionHandle()` returned. The scope resolves the session
   * from it instead of reading the request.
   */
  readonly session?: SessionHandle;
  /**
   * The active tenant, as for `bsb.context({ tenant })`. Next.js keys the
   * private cache on your function's arguments, so take the tenant as an
   * argument and pass it through; never read it from anywhere else.
   */
  readonly tenant?: string;
}

export interface RemoteCachedOptions<
  T extends string = string,
> extends CachedEntryOptions<T> {
  readonly scope: "remote";
  /** The key `bsb.remote()` passed to the function. */
  readonly key: RemoteCacheKey;
}

export type CachedOptions<T extends string = string> =
  | PrivateCachedOptions<T>
  | RemoteCachedOptions<T>;

/**
 * Options of `bsb.public()`: the entry options of `bsb.cached()` without a
 * session, `stage` or scope, plus the tenant.
 */
export interface PublicCachedOptions<
  T extends string = string,
> extends CachedEntryOptions<T> {
  /**
   * The tenant the read is for, as for `bsb.context({ tenant })`. Next.js keys
   * a `"use cache"` entry on your function's arguments, so take the tenant as
   * an argument and pass it through; never read it from the request.
   */
  readonly tenant?: string;
}

export type BootstrapOptions<
  T extends string = string,
  S extends ReadSet = ReadSet,
> = CachedOptions<T> &
  Omit<BootstrapCallOptions<S>, "tenant"> & {
    /**
     * Where to send the caller when `session_active()` is false, with
     * `?reason=session_not_found`, or `?reason=user_banned` for a banned user.
     * Without it the result has `sessionActive: false`, and the entry isn't
     * kept.
     */
    readonly redirect?: string;
    /**
     * The `reason` query value on the redirect, as in `VerifySessionOptions`.
     * Defaults to `session_not_found` and `user_banned`; `signedOut`, for a
     * caller `require: "user"` turns away, defaults to `signed_out`.
     */
    readonly reasons?: {
      readonly ended?: string;
      readonly banned?: string;
      readonly signedOut?: string;
    };
    /**
     * Keeps the wrapper's answer (data, reads, subject and permissions) in the
     * kept store, per user, session and tenant, expired by writes to the tables
     * the wrapper reads, so a cold page or a new instance skips the call. A
     * session that ended is served from the store for at most `life.revalidate`
     * seconds (default 30), unless `bsb.evictSession()` ran for the user. Needs
     * a shared kept store to help across instances.
     */
    readonly kept?: true | { readonly life?: { readonly revalidate?: number } };
  } & (
    | { readonly require?: undefined }
    | {
        /**
         * `"user"` sends a caller without a user session (signed out, an API
         * key or a service caller) to `redirect` too, with
         * `?reason=signed_out`, so the result is always an active user session.
         * Needs `redirect`.
         */
        readonly require: "user";
        readonly redirect: string;
      }
  );

export type { Access, Bootstrap } from "../server/bootstrap.ts";

/** A tenant record: what a resolver returns, and what `scope.tenant` is. */
export interface TenantRecord {
  readonly id: string;
}

export interface NextTenants {
  /** The kind a string `TenantRef` is read as. Defaults to `"id"`. */
  readonly by?: string;
  /** One resolver per kind; `id` needs none and reads the id as given. */
  readonly resolve: Readonly<
    Record<
      string,
      (value: string) => Promise<TenantRecord | null> | TenantRecord | null
    >
  >;
}

/**
 * Names a tenant: a string read as `NextTenants.by`, `{ id }`, or `{ <kind>:
 * string }` for a resolver kind.
 */
export type TenantRef = string | { readonly [kind: string]: string };

/** `PrivateCachedOptions` minus what the helpers fill in. */
export type ScopeCallOptions<T extends string = string> = Omit<
  PrivateCachedOptions<T>,
  "scope" | "tenant"
> & {
  /**
   * Start the permission check without waiting for it and gate `db` instead: a
   * read starts at once under RLS and settles after the check, so a cold call
   * costs one round trip. A refusal settles the read with a `forbidden`,
   * `not_found` or `unauthorized` error Result. Do not read `can` or `granted`
   * as proof before the first read settles.
   */
  readonly gate?: boolean;
};

/** What `bsb.auth()` returns: the cached context plus the caller. */
export type AuthScope<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  D,
  Ref,
> = CachedContext<M, F, E, C, P, B, D> & {
  /** The signed-in user. */
  readonly user: Extract<AuthSession<C, P>, { kind: "user" }>["user"];
  /** Whether the caller holds `permission` in the scope's tenant. */
  can(permission: Ref): Promise<boolean>;
};

/** What `bsb.tenant(ref)` and `bsb.activeTenant()` return. */
export type TenantScope<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  D,
  Ref,
> = AuthScope<M, F, E, C, P, B, D, Ref> & {
  /** The record the app's resolver returned. */
  readonly tenant: TenantRecord;
  /** Whether the permission check passed; `true` when none was asked for. */
  readonly granted: true;
};

/** A `bsb.bootstrap({ require: "user" })` result: an active user session. */
export type UserBootstrap<
  C = unknown,
  P = unknown,
  T = unknown,
  R = Readonly<Record<string, unknown>>,
> = Bootstrap<C, P, T, R> & {
  readonly session: Extract<AuthSession<C, P>, { readonly kind: "user" }>;
  readonly sessionActive: true;
};

export interface NextRootParams {
  /** `locale` from `next/root-params`. */
  readonly locale?: () => Promise<string | undefined>;
  /** `brand` from `next/root-params`. */
  readonly brand?: () => Promise<string | undefined>;
  /** `tenant` from `next/root-params`; `NextOptions.tenant` falls back to it. */
  readonly tenant?: () => Promise<string | undefined>;
}

export type CachedContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
  // oxlint-disable-next-line typescript/no-explicit-any -- as ServerContext
  D = any,
> = ServerContext<M, F, E, C, P, B, D> & {
  readonly session: AuthSession<C, P>;
};

/**
 * The second argument of `revalidateTag`: a `cacheLife` profile name or `{
 * expire }`.
 */
export type RevalidateProfile = string | { readonly expire?: number };

export interface NextCacheOptions {
  /**
   * How a mutation outside a Server Action (a route handler, a webhook) expires
   * its tags with `revalidateTag`. Defaults to `{ expire: 0 }`, so the next
   * read waits for fresh data; `'max'` serves the stale entry while it
   * revalidates.
   */
  readonly revalidate?: string | { readonly expire?: number };
}

export interface RequireAalOptions {
  /**
   * Page that enrolls or challenges a second factor. Signed-in users below the
   * level are redirected there with `?next=<path>`; without it they get a 403
   * Problem Details response.
   */
  readonly redirect?: string;
  /** Paths that need the level. Defaults to every path but `redirect`. */
  readonly match?: (pathname: string) => boolean;
}

/**
 * What a `resource` loader gets in Next.js: the caller's context, with the
 * checked tenant.
 */
export type NextResource<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
  // oxlint-disable-next-line typescript/no-explicit-any -- as ServerContext
  D = any,
> = ServerContext<M, F, E, C, P, B, D> & ResourceLoaderContext<C, P>;
