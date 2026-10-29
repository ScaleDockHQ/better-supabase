import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { UserClaims } from "@supabase/server";
import type { NextRequest } from "next/server.js";

import type { AuthState } from "../auth/resolve.ts";
import type { CookieScope } from "../auth/session.ts";
import type {
  AuthorizeUrlParams,
  ExistingAccount,
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
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { ReadSet } from "../core/read-set.ts";
import type { QuerySpec } from "../core/spec.ts";
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
   * Methods that run `protect`. Defaults to `GET` and `HEAD`, so a Server
   * Action POST is not redirected before the action runs. Set `true` to include
   * mutations, or pass the methods yourself.
   */
  readonly protectMethods?: true | readonly string[];
  /**
   * Post-processes the final response; return a new one to replace it. The
   * session cookies and cache headers are added to a replacement too.
   */
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
  V extends AuthzVersionCache = AuthzVersionCache,
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
  context(options?: ScopeOptions): Promise<ServerContext<M, F, E, C, P, B>>;
  context(
    request: Request | undefined,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>>;
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
  ): Promise<ServerContext<M, F, E, C, P, B>>;
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
  ): Promise<CachedContext<M, F, E, C, P, B>>;
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
   * One call for a page's user data: runs the sessions module's
   * `bootstrap_<rpc>` wrapper, which checks `session_active()` and returns the
   * caller's authorization version with the app function's data. Call it as the
   * first statement of a cache function, like `bsb.cached()`; React's `cache()`
   * runs the call once per request and key. A `false` `sessionActive` evicts
   * the user's entries and redirects to `redirect` when it is set.
   */
  bootstrap<T = unknown>(
    options: BootstrapOptions<Extract<keyof M, string>>,
  ): Promise<Bootstrap<C, P, T>>;
  /**
   * The context, tenant and permission checks for a bootstrap result (or a
   * snapshot), bound to its authorization version, so islands stop rebuilding
   * their context one by one. In a remote scope pass the key.
   */
  getAccess(
    source?: Bootstrap<C, P> | SessionSnapshot<C> | null,
    options?: { readonly key?: RemoteCacheKey },
  ): Promise<Access<ServerContext<M, F, E, C, P, B>, C, P, Ref>>;
  /** `rootParams.locale()`, or `undefined` without one or outside a render. */
  locale(): Promise<string | undefined>;
  /** `rootParams.brand()`, or `undefined` without one or outside a render. */
  brand(): Promise<string | undefined>;
  /** `rootParams.tenant()`, or `undefined` without one or outside a render. */
  tenant(): Promise<string | undefined>;
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
   *   { input: Invite, requireTenant: true, roles: ["admin"] },
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
   *   requireTenant: true,
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
   * else `options.fallback` (`/`). Reads later in the same request
   * (`getClaims()`, `claims()`, `context()`) see the new session.
   */
  signInWithPassword(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Verifies an email link's `token_hash` (sign-up, invite, magic link,
   * recovery, email change) or an emailed code, then commits the session like
   * `signInWithPassword`. The new session replaces any session the request
   * carried.
   */
  verifyOtp(
    params: VerifyOtpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * The Auth server's OAuth URL for `provider`, for a `redirect()`. It writes
   * the PKCE verifier cookie (httpOnly, `lax`, 10 minutes) that
   * `exchangeCodeForSession` reads. `next` rides on `redirectTo` as `?next=`
   * when it is a same-origin path.
   */
  signInWithOAuth(
    params: SignInWithOAuthParams,
  ): Promise<{ readonly url: string }>;
  /**
   * Exchanges the callback's `?code=` and the PKCE verifier cookie for a
   * session, deletes the verifier cookie and commits the session like
   * `signInWithPassword`.
   */
  exchangeCodeForSession(
    params: ExchangeCodeParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Challenges and verifies an MFA factor for the signed-in user and commits
   * the `aal2` session; `mfa` is then false.
   */
  verifyMfa(
    params: MfaVerification,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Ends the session on the Auth server first (`scope`, `local` by default),
   * then clears the session cookies (also at `cookieScopes`), forgets the
   * verified sessions and expires its cache tags. `others` keeps this session
   * and its cookies, and still forgets the verified sessions. Reads later in
   * the same request are signed out.
   */
  signOut(
    params?: SignOutParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Emails a magic link and a code. It writes the PKCE verifier cookie like
   * `signInWithOAuth`, so the link's `?code=` goes to `exchangeCodeForSession`,
   * and the code to `verifyOtp` with `type: "email"`. Returns `null`: nothing
   * is signed in yet.
   */
  signInWithOtp(params: SignInWithOtpParams): Promise<ActionResult<null>>;
  /**
   * Emails a password reset link with the PKCE verifier cookie.
   * `exchangeCodeForSession` on the callback signs the user in; the app then
   * asks for the new password. Auth answers the same whether or not an account
   * has the email.
   */
  resetPasswordForEmail(
    params: ResetPasswordParams,
  ): Promise<ActionResult<null>>;
  /**
   * Signs up with an email and a password. With email confirmation on, it
   * emails the confirmation link with the PKCE verifier cookie and returns
   * `null`. With it off, Auth returns a session, committed like
   * `signInWithPassword`. When the email already has a confirmed account, Auth
   * sends nothing and this returns `{ existingAccount: true }`, so the app can
   * email the owner itself. Show the user the same screen either way, so the
   * page doesn't tell who has an account.
   */
  signUp(
    params: SignUpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn | ExistingAccount | null>>;
  /**
   * Emails the sign-up confirmation or the email change link again, with a new
   * PKCE verifier cookie.
   */
  resend(params: ResendParams): Promise<ActionResult<null>>;
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

/**
 * Where an email link lands. The verifier cookie lives 10 minutes and holds one
 * flow: a newer `signInWithOAuth` or email flow in the same browser replaces
 * it.
 */
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
}

export interface RemoteOptions<
  C = unknown,
  A extends readonly unknown[] = readonly unknown[],
> {
  /** Defaults to `"session"`. */
  readonly share?: CacheShare<C>;
  /**
   * The active tenant from the function's arguments, as for `bsb.context({
   * tenant })`.
   */
  readonly tenant?: (...args: A) => string | undefined;
}

interface CachedEntryOptions<T extends string = string> {
  /**
   * `cacheLife` for the entry. Pass a permission snapshot's lifetime as `stale`
   * so the entry goes stale with the snapshot too.
   */
  readonly life?: CachedLife;
  /** More tags for the entry, e.g. `snapshotTag(sub)` or `organization:<id>`. */
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

export interface PrivateCachedOptions<T extends string = string>
  extends ScopeOptions, CachedEntryOptions<T> {
  /** Defaults to `"private"`. */
  readonly scope?: "private";
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

export type BootstrapOptions<T extends string = string> = CachedOptions<T> &
  Omit<BootstrapCallOptions, "tenant"> & {
    /**
     * Where to send the caller when `session_active()` is false, with
     * `?reason=session_not_found`, or `?reason=user_banned` for a banned user.
     * Without it the result has `sessionActive: false`, and the entry isn't
     * kept.
     */
    readonly redirect?: string;
    /**
     * The `reason` query value on the redirect, as in `VerifySessionOptions`.
     * Defaults to `session_not_found` and `user_banned`.
     */
    readonly reasons?: { readonly ended?: string; readonly banned?: string };
  };

export type { Access, Bootstrap } from "../server/bootstrap.ts";

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
