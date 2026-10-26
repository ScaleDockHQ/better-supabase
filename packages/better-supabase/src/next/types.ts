import type { StandardSchemaV1 } from "@standard-schema/spec";
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
import type { ReadSet } from "../core/read-set.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { TagOptions } from "../core/tags.ts";
import type { CountRunner, LiveCountSeed } from "../realtime/live.ts";
import type { BindingName } from "../records/bindings.ts";
import type { RecordType, RecordTypeBlocks } from "../records/record-type.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
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
import type { ResourceMap } from "../server/resources.ts";
import type { GuardOptions } from "../server/respond.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
  ServerOptions,
  SharedServer,
} from "../server/server-types.ts";
import type { SupportStartRequest } from "../server/support.ts";
import type { DbBudget } from "./collector.ts";
import type { RecordServer } from "./record.ts";
import type { NextResourceRoutes, NextResourcesOptions } from "./resources.ts";

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
   * A prefetch never refreshes, so a session cookie whose token expired
   * resolves to `{ kind: 'anon', reason: 'expired' }` there. `'protect'` (the
   * default) passes that to `protect` like any other caller. `'render'` skips
   * `protect` for it, so the prefetch renders signed out instead of caching a
   * redirect to sign-in; `sessionStale` keeps that view out of the App Shell,
   * and the navigation itself refreshes the session.
   */
  readonly expiredPrefetch?: "protect" | "render";
  /**
   * Methods that run `protect`. Defaults to `GET` and `HEAD`, so a Server
   * Action POST is not redirected before the action runs. Set `true` to include
   * mutations, or pass the methods yourself.
   */
  readonly protectMethods?: true | readonly string[];
  /** Post-processes the final response; return a new one to replace it. */
  readonly after?: (
    response: Response,
    auth: AuthState<C, P>,
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
  readonly refreshSkewSeconds?: number;
  /**
   * Ask Auth whether the session still exists (one network call), on top-level
   * document loads only. `true` checks every document load.
   */
  readonly endedSession?: true | EndedSessionOptions;
  /**
   * Called when a refresh failed because the Auth server was unreachable, timed
   * out or answered 5xx or 429. When the access token couldn't be kept
   * (`event.kept` is false), a returned `Response` replaces the proxy's
   * response, such as a 503 with `Retry-After`. A throw is logged and ignored.
   */
  readonly onAuthOutage?: AuthOutageHook;
}

export interface EndedSessionOptions {
  /**
   * The paths whose document loads check the session, such as `/settings`.
   * Defaults to every document load. Client navigations, prefetches and
   * mutations never check.
   */
  readonly paths?: readonly string[];
  readonly redirect?: string;
  /**
   * The `reason` query value on the redirect. Defaults to `session_ended` and
   * `account_banned`.
   */
  readonly reasons?: { readonly ended?: string; readonly banned?: string };
}

export interface ActionOptions<
  S extends StandardSchemaV1 | undefined,
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
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
  readonly tenant?: (input: ActionParsed<S>) => string | undefined;
}

/**
 * How `blockAction` calls the method: without `args` it passes the validated
 * input as the only argument, so `args` is required when the method takes
 * anything else.
 */
export type BlockActionArgs<S, A, Ctx> = [ActionParsed<S>] extends A
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

export interface BetterNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
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
  context(options?: ScopeOptions): Promise<ServerContext<M, F, E, C, P, B>>;
  context(
    request: Request | undefined,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  /**
   * The verified caller as serializable data (no token, no clients), memoized
   * per request. Wrap it in a `'use cache: private'` function with Cache
   * Components and pass the promise to `<SessionProvider>`.
   */
  session(): Promise<AuthSession<C, P>>;
  /**
   * The verified session of the incoming request, shared by every cache scope
   * of the render: the first scope verifies the token and the others await that
   * verification, so ten `'use cache: private'` islands verify once. It awaits
   * `cookies()` before reading the clock, so it is safe in a private cache and
   * outside one. `null` for anyone but a signed-in user. Pass the snapshot to
   * `contextFromSession()` inside an island.
   *
   * ```tsx
   * async function Island() {
   *   "use cache: private";
   *   const session = await bsb.getRequestSession();
   *   const { db } = await bsb.contextFromSession(session);
   * }
   * ```
   */
  getRequestSession(): Promise<SessionSnapshot<C> | null>;
  /**
   * The context for a session and its token, without reading the request. The
   * token is verified again (memoized, no network call); a token for another
   * user than `session` gives an `invalid` context.
   */
  contextForSession(
    session: AuthSession<C, P>,
    options: { readonly token: string | null },
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  /**
   * First statement of an app-authored `'use cache: private'` function: sets
   * `cacheLife` from the session's expiry (`sessionStale`, capped by
   * `life.stale`), tags the entry `bsb:session:<user id>` plus `tags`, and
   * returns the caller's context plus `session`.
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
  ): Promise<CachedContext<M, F, E, C, P, B>>;
  /**
   * Drops every `bsb.cached()` entry of a user, e.g. after a role change, and
   * the entries tagged with `tags` (such as a permission snapshot's tag). In a
   * Server Action it also re-renders the caller's page, so no `refresh()` is
   * needed. It reaches server caches and the caller's router only: another
   * user's browser keeps its `'use cache: private'` entries until they go stale
   * or that user's token changes.
   */
  invalidateSession(
    userId: string,
    options?: { readonly tags?: readonly string[] },
  ): void;
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
      ctx: ServerContext<M, F, E, C, P, B> &
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
   *   { input: Invite, requireOrganization: true, roles: ["admin"] },
   *   async (input, { db, tenant }) =>
   *     db.invitations.create({ ...input, organizationId: tenant }),
   * );
   * ```
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: ActionOptions<S, C, P, R, Ref, NextResource<M, F, E, C, P, B>>,
    fn: (
      input: ActionParsed<S>,
      ctx: ServerContext<M, F, E, C, P, B> & AuthorizedContext<C, P, R>,
    ) => Promise<T> | T,
  ): (input: ActionInput<S>) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
  /**
   * A server action that calls one block method as the caller, with the same
   * guard, validation and authorize checks as `action`.
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
  >(
    client: (ctx: ServerContext<M, F, E, C, P, B>) => Cl,
    method: K & BlockMethodName<Cl>,
    options: ActionOptions<S, C, P, R, Ref, NextResource<M, F, E, C, P, B>> &
      BlockActionArgs<
        S,
        BlockArgsOf<Cl, K & BlockMethodName<Cl>>,
        ServerContext<M, F, E, C, P, B> & AuthorizedContext<C, P, R>
      >,
  ): (
    input: ActionInput<S>,
  ) => Promise<ActionResult<BlockDataOf<Cl, K & BlockMethodName<Cl>>>>;
  /**
   * One record type's server binding (`defineRecordType`, which `gen` writes to
   * `records/<type>.ts`): `load` settles each block's binding for a record in a
   * Server Component, `actions` holds one Server Action per binding write, and
   * `tags` lists the record's cache tags. Each write drops the binding's and
   * the record's tags in the caller's organization.
   *
   * ```ts
   * const customer = bsb.record(customerRecord);
   * const { bindings, can } = await customer.load(id, {
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
   * For Server Components: the caller's context, or the Next.js interrupt for a
   * refused caller. `unauthorized` calls `unauthorized()`, `forbidden` calls
   * `forbidden()` (both need `experimental.authInterrupts`, else `notFound()`),
   * and `not_found` calls `notFound()`.
   *
   * ```ts
   * const { db, tenant } = await bsb.require({
   *   requireOrganization: true,
   *   roles: ["admin"],
   * });
   * ```
   */
  require<R extends boolean = false>(
    options?: RequireOptions<C, P, R, Ref, NextResource<M, F, E, C, P, B>>,
  ): Promise<ServerContext<M, F, E, C, P, B> & AuthorizedContext<C, P, R>>;
  /**
   * REST resources for a catch-all route, matching the API model: collections,
   * items and actions, as the caller (RLS), behind the guard in `options`, with
   * Problem Details errors. An unknown path answers 404 before auth resolves.
   *
   * ```ts
   * // app/api/[...path]/route.ts
   * export const { GET, POST, PATCH, PUT, DELETE } = bsb.resources(
   *   { customers: true },
   *   { basePath: "/api" },
   * );
   * ```
   */
  resources(
    map: ResourceMap<M, Ref, ServerContext<M, F, E, C, P, B>["db"]>,
    options?: NextResourcesOptions,
  ): NextResourceRoutes;
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
   * Tags the current `"use cache"` scope with every table the specs (or a read
   * set) read, plus the row of each `get`, so any mutation that changes one
   * revalidates it.
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
   * Signs in with an email and a password from a server action. It writes the
   * session cookies, stores the verified session for the next render and
   * returns `redirectTo`: `credentials.next` when it is a same-origin path,
   * else `options.fallback` (`/`). Reads later in the same request see the new
   * session.
   */
  signIn(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  /** The same as `signIn`. */
  signInWithPassword(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  /**
   * Verifies an email link's `token_hash` (sign-up, invite, magic link,
   * recovery, email change) or an emailed code, then commits the session like
   * `signIn`. The new session replaces any session the request carried.
   */
  verifyOtp(
    params: VerifyOtpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  /**
   * The Auth server's OAuth URL for `provider`, for a `redirect()`. It writes
   * the PKCE verifier cookie (httpOnly, `lax`, 10 minutes) that `exchangeCode`
   * reads. `next` rides on `redirectTo` as `?next=` when it is a same-origin
   * path.
   */
  authorizeUrl(params: OAuthStart): Promise<{ readonly url: string }>;
  /**
   * Exchanges the callback's `?code=` and the PKCE verifier cookie for a
   * session, deletes the verifier cookie and commits the session like
   * `signIn`.
   */
  exchangeCode(
    params: CodeExchange,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  /**
   * Challenges and verifies an MFA factor for the signed-in user and commits
   * the `aal2` session; `mfa` is then false.
   */
  verifyMfa(
    params: MfaVerification,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  /**
   * Ends the session on the Auth server first (`scope`, `local` by default),
   * then clears the session cookies (also at `cookieScopes`), forgets the
   * verified session and expires its cache tags. `others` keeps this session.
   * Reads later in the same request are signed out.
   */
  signOut(
    params?: SignOutParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
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
  /** Checked before use, like `signIn`'s. */
  readonly next?: string | null;
};

/** `authorizeUrl` input. */
export interface OAuthStart extends AuthorizeUrlParams {
  /** Where to go after the callback; checked before use. */
  readonly next?: string | null;
}

/** `exchangeCode` input: the callback's `?code=` and `?next=`. */
export interface CodeExchange {
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

/** What the sign-in and sign-out helpers return. */
export interface SignedIn<C = unknown> {
  /** `next` when it is a same-origin path, else `fallback` (`/`). */
  readonly redirectTo: string;
  /**
   * The user has a verified MFA factor and the session is not `aal2` yet: send
   * them to the challenge (with `redirectTo` as its `next`) before
   * `redirectTo`. Advisory: keep the proxy and `action({ aal: 2 })` gates.
   */
  readonly mfa: boolean;
  /**
   * The committed session, `null` after a sign-out. Pass it to
   * `contextFromSession` to build the landing context. It holds the access
   * token, so keep it on the server.
   */
  readonly session: SessionSnapshot<C> | null;
}

/** What `startSupport` returns: plain data, safe across the action boundary. */
export interface SupportStarted {
  readonly sessionId: string;
  readonly targetUserId: string;
  readonly readOnly: boolean;
  /** ISO 8601. */
  readonly expiresAt: string;
}

export interface SessionStaleOptions {
  /**
   * With fewer seconds left on the token, the view is not reused at all (0):
   * Next.js would not prefetch it anyway. Defaults to 30, and values below 30
   * count as 30: the client router keeps any entry for at least 30 seconds, so
   * a shorter stale time would outlive the token.
   */
  readonly min?: number;
  /** 300 (5 minutes) joins the route's App Shell. Defaults to 300. */
  readonly max?: number;
}

export interface CachedOptions<T extends string = string> extends ScopeOptions {
  /**
   * The active tenant, as for `bsb.context({ tenant })`. Next.js keys the
   * private cache on your function's arguments, so take the tenant as an
   * argument and pass it through; never read it from anywhere else.
   */
  readonly tenant?: string;
  /**
   * `cacheLife` for the entry. `stale` is `sessionStale`, and never more than
   * `stale` when it is set: pass a permission snapshot's lifetime so the entry
   * goes stale with the snapshot too.
   */
  readonly life?: SessionStaleOptions & {
    readonly stale?: number;
    readonly revalidate?: number;
    readonly expire?: number;
  };
  /**
   * More `cacheTag`s for the entry, e.g. `snapshotTag(sub)` or
   * `organization:<id>`.
   */
  readonly tags?: readonly string[];
  /**
   * Tables the entry reads, so the `updateTag` after a mutation drops it:
   * `bsb:<table>`, or with an active tenant `bsb:<table>@<tenant>` and
   * `bsb:<table>@*`, so other tenants' writes leave it cached.
   */
  readonly tables?: readonly T[];
  /** With `tables`, also tags the row `bsb:<first table>:<id>`. */
  readonly id?: string | number;
}

export type CachedContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> = ServerContext<M, F, E, C, P, B> & { readonly session: AuthSession<C, P> };

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
> = ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>;
