import type { SupabaseClient } from "@supabase/supabase-js";

import type { ImpersonationOptions } from "../auth/impersonation.ts";
import type {
  AuthResolution,
  AuthState,
  ResolveAuthOptions,
} from "../auth/resolve.ts";
import type { CookieWrite } from "../auth/session.ts";
import type { AnyAuthorizer } from "../core/authorizer.ts";
import type {
  AuthorizationHooks,
  TicketSubject,
} from "../core/contracts/authorization-hooks.ts";
import type { EventHub } from "../core/events.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { AsyncResult } from "../core/result.ts";
import type { StatsRecorder, DbStats } from "../core/stats.ts";
import type { CredentialProvider } from "../credentials/provider.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";
import type { EventSink } from "../events/index.ts";
import type { BetterPostgres, SqlClaims } from "../postgres/pool.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { StorageApi } from "../storage/storage-api.ts";
import type {
  DeleteAccountOptions,
  DeleteAccountResult,
} from "./delete-account.ts";
import type { LiteDriver } from "./lite.ts";
import type { ReplicaState } from "./replicas.ts";
import type { RequestIdOptions } from "./request-ids.ts";
import type { ActiveSupport, SupportApi, SupportSessions } from "./support.ts";
import type {
  EndSessionsResult,
  SuspendAccountOptions,
  SuspendAccountResult,
} from "./suspend-account.ts";

/**
 * PostgREST request settings for the caller's repositories and the shared
 * service and anon clients, the `db` options supabase-js takes.
 */
export interface ServerDbOptions {
  /** Aborts each PostgREST request after this many milliseconds with a `timeout` error. */
  readonly timeout?: number;
  /**
   * postgrest-js retries of idempotent requests (GET and HEAD) on network
   * errors, 503 and 520. Defaults to postgrest-js's setting, which is on.
   */
  readonly retry?: boolean;
  /**
   * The longest query string one read sends. Defaults to the definition's
   * `urlLengthLimit`, else 6000.
   */
  readonly urlLengthLimit?: number;
}

export interface ServerOptions {
  /**
   * Defaults to the variables `getEnv` from `@supabase/middleware` reads:
   * Workers bindings, then `process.env`, then `Deno.env`.
   */
  readonly env?: BetterSupabaseEnv;
  /** Enables `ctx.sql` and `actingAs()`. */
  readonly postgres?: BetterPostgres;
  readonly auth?: Omit<ResolveAuthOptions, "env">;
  /**
   * `"lite"` for Supabase Lite: tokens verify with `SUPABASE_JWT_SECRET`, no
   * JWKS prefetch, and `rpc()` is `unsupported` on its SQLite drivers.
   */
  readonly backend?: "supabase" | "lite";
  /** Lite's `[db] driver`, default `sqlite-postgres`; `postgres` needs `postgres`. */
  readonly liteDriver?: LiteDriver;
  /**
   * Fetch the JWKS when the server is created, so the first request verifies
   * its token without waiting for it. Applies when neither `auth.jwks` nor
   * `env.jwks` (`SUPABASE_JWKS`) holds the keys inline. Defaults to true, except under `NODE_ENV=test`.
   */
  readonly prefetchJwks?: boolean;
  /**
   * Extra headers on the caller's PostgREST requests, readable in Postgres as
   * `current_setting('request.headers')` (channel, request id, client IP for audit).
   */
  readonly headers?: (request: Request) => Readonly<Record<string, string>>;
  readonly requestIds?: RequestIdOptions | false;
  /**
   * PostgREST URL for the caller's reads: a read replica or the `<ref>-all`
   * load balancer. Defaults to `SUPABASE_READ_URL`; `false` reads from the
   * primary.
   */
  readonly readUrl?: string | false;
  /**
   * `fetch` for the PostgREST and supabase-js clients, e.g. `tracedFetch()`
   * from `better-supabase/otel`. Auth refreshes use `auth.fetch`.
   */
  readonly fetch?: typeof globalThis.fetch;
  readonly replicas?: {
    /** How long the next requests read from the primary after a write. Defaults to 5 s. */
    readonly pinMs?: number;
  };
  /**
   * The active tenant of a request when it doesn't come from a claim, e.g.
   * from a URL slug (`blocks.access.activeTenant: 'resolver'`). It becomes
   * `context.tenant` for the `tenant()` plugin, the `better_supabase.tenant`
   * setting over Postgres and the `x-bs-tenant` header over PostgREST, which
   * `current_tenant_id()` reads only while the caller is a member. Async
   * resolvers need `context(request)`; `contextFromResolution` takes
   * `options.tenant` instead. Under `createNext`, Server Components and
   * actions pass a request with the incoming headers and a placeholder URL,
   * so read a header there, not the path.
   */
  readonly tenant?: (
    request: Request,
    auth: AuthState,
  ) => string | undefined | PromiseLike<string | undefined>;
  /**
   * Support sessions ("view as user") from `supportSessions(options)`: a platform admin's requests that carry
   * the support cookie run as the target user, read-only by default. Needs
   * `postgres`, since the target's queries run over direct Postgres.
   */
  readonly support?: SupportSessions;
  /**
   * The claims `forContext()` adds for a user, the ones a custom access token
   * hook would put in their token (roles, organization lists). Read them
   * fresh: a job can run after the user lost access. `sub`, `role`, `act` and
   * `tenant_id` come from the context and win.
   */
  readonly claimsFor?: (
    userId: string,
    context: RequestContext,
  ) => SqlClaims | PromiseLike<SqlClaims>;
  /** PostgREST request settings: `timeout`, `retry` and `urlLengthLimit`. */
  readonly db?: ServerDbOptions;
  /**
   * Resolves the `credential_ref`s third-party calls use, e.g.
   * `vaultCredentials()` from `better-supabase/credentials`. It becomes
   * `ctx.credentials`; pass `subjectFor(ctx)` as the subject.
   */
  readonly credentials?: CredentialProvider;
  /**
   * Where the server's audit trail goes, such as `audit.sink()` from
   * `better-supabase/blocks/audit`. `suspendAccount`, `deleteAccount` and
   * `endSessions` send `dev.better-supabase.account.*` CloudEvents, and
   * `support.denied` events are forwarded. A failed send is logged and never
   * fails the action.
   */
  readonly audit?: EventSink;
  /**
   * The authorization decision point (`Authorizer` v1) that resources,
   * actions, routes and MCP tools ask for their `permission`. Without one, a
   * declared permission denies.
   */
  readonly authorizer?: AnyAuthorizer;
  /**
   * The runtime hooks of an authorization provider (`AuthorizationHooks`
   * v1). Support sessions read `support.authorize` and `approverOf`, and
   * `forContext` reads `tickets.subject`, when their own options are unset.
   */
  readonly authorization?: AuthorizationHooks;
}

export interface ForContextOptions {
  /** Recorded as `act.reason` when the context carries an impersonator. Defaults to `"job"`. */
  readonly reason?: string;
  /**
   * Resolves a context's `ticket` into the context the work runs as.
   * Defaults to `ServerOptions.authorization.tickets.subject`.
   */
  readonly ticket?: TicketSubject;
  /**
   * The permission keys the work may use (`*` and `prefix.*` match as in
   * grants). Set as the `bs_permission_cap` claim, which the access
   * functions check through `better_supabase.cap_allows`, so a key outside
   * the cap is refused even when the user holds it. A cap the context
   * already carries is narrowed, never widened.
   */
  readonly permissions?: readonly string[];
}

/** The header `current_tenant_id()` reads over the Data API. */
export const TENANT_HEADER = "x-bs-tenant";

export interface ServerContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  readonly auth: AuthState<C, P>;
  readonly resolution: AuthResolution<C, P>;
  /**
   * supabase-js client scoped to the caller (RLS applies). Throws in a
   * support session: Realtime, Storage and Auth would act as the admin.
   */
  readonly supabase: SupabaseClient;
  /** Repositories over PostgREST as the caller. */
  readonly db: Db<M, F, E, SupabaseClient, B>;
  /** Repositories over direct Postgres as the caller, when `postgres` is configured. */
  readonly sql: Db<M, F, E, undefined, B> | undefined;
  /** Calls, waves, tables and time for `db` and `sql` together. */
  stats(): DbStats;
  /** Where `db` reads go, when a read URL is configured. */
  readonly replica: ReplicaState | undefined;
  /**
   * `response` with this request's cookies: refreshed session cookies
   * (`resolution.apply`) and, after a write, `bs-primary-until`.
   */
  apply(response: Response): Response;
  /**
   * The cookies `apply` would set, for frameworks that write cookies through
   * a cookie store instead of a response (`cookies().set`, `setResponseHeaders`).
   * Read it after the handler ran: a write adds `bs-primary-until`.
   */
  cookies(): readonly CookieWrite[];
  /**
   * Set while an admin views the app as another user: `auth`, `db` and
   * `sql` are the target's, and `resolution` stays the admin's.
   */
  readonly support?: ActiveSupport;
  /**
   * Set in a support session, where `ctx.supabase` throws: Storage read as
   * the target, with the file API of `supabase.storage`. Listings, `exists`
   * and `info` run over Postgres as the target; downloads and signed URLs
   * are checked there, then served with the service client. Writes are
   * refused. Needs `SUPABASE_SECRET_KEY`.
   */
  readonly storage?: StorageApi;
  /** `options.credentials`, when the server has one. */
  readonly credentials?: CredentialProvider;
  readonly requestId?: string;
  readonly correlationId?: string;
}

export interface ContextOptions {
  readonly refresh?: boolean;
  /** Read the session cookie. Defaults to true; `false` resolves bearer tokens only. */
  readonly cookies?: boolean;
  /** Epoch ms until which `db` reads from the primary (the `bs-primary-until` cookie). */
  readonly pinnedUntil?: number;
  /** Also records this context's calls into a request-wide recorder. */
  readonly stats?: StatsRecorder;
  /** The active tenant, instead of `ServerOptions.tenant`. */
  readonly tenant?: string;
  /**
   * The request's support session, from `support.current()`. `context()`
   * looks it up itself; `contextFromResolution` only uses this.
   */
  readonly support?: ActiveSupport;
  readonly requestId?: string;
  readonly correlationId?: string;
}

export interface BetterServer<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  readonly env: BetterSupabaseEnv;
  /** The definition's events; adapters pass `events.settled()` to `waitUntil`. */
  readonly events: EventHub;
  resolve(
    request: Request,
    options?: {
      readonly refresh?: boolean;
      readonly cookies?: boolean;
      readonly checkSession?: boolean;
    },
  ): Promise<AuthResolution<C, P>>;
  /**
   * Resolves auth and binds repositories to the caller. Refreshes an expired
   * cookie session only with `refresh: true`; send `ctx.apply(response)`.
   */
  context(
    request: Request,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P, B>>;
  /**
   * The context for a resolution from `resolve(request)`, so one resolution
   * can back several contexts without verifying the token again.
   */
  contextFromResolution(
    resolution: AuthResolution<C, P>,
    request: Request,
    options?: Omit<ContextOptions, "refresh">,
  ): ServerContext<M, F, E, C, P, B>;
  /** The context for an auth state resolved elsewhere (the proxy, a queue message). */
  contextFor(
    auth: AuthState<C, P>,
    options?: ContextOptions,
  ): ServerContext<M, F, E, C, P, B>;
  /** A stateless supabase-js client for an auth state, optionally with extra request headers. */
  supabaseFor(
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ): SupabaseClient;
  /**
   * Repositories for an auth state (e.g. one resolved by the proxy). With
   * `options.support`, from `support.resolve()` or `support.current()`, they
   * run as the support session's target, like `contextFor(auth, { support }).db`.
   */
  dbFor(
    auth: AuthState,
    context?: RequestContext,
    options?: { readonly support?: ActiveSupport },
  ): Db<M, F, E, SupabaseClient, B>;
  /** Service-role repositories. Bypasses RLS; the actor is `service`. */
  admin(context?: RequestContext): Db<M, F, E, SupabaseClient, B>;
  /**
   * Deletes a user: the Auth user, then their objects in `buckets`, then a
   * `mutation` notice for `auth.users`. Needs the secret key. With
   * `postgres`, a delete the database refuses returns its own error and
   * hint. Access tokens already issued stay valid until they expire.
   */
  deleteAccount(
    userId: string,
    options?: DeleteAccountOptions,
  ): AsyncResult<DeleteAccountResult>;
  endSessions(userId: string): AsyncResult<EndSessionsResult>;
  /**
   * Bans the user in Auth and keeps their sessions, so Auth answers with
   * `user_banned` (`endSessions: true` deletes them too). Lifting the ban
   * ends the sessions first, so the user signs in again.
   */
  suspendAccount(
    userId: string,
    options: SuspendAccountOptions,
  ): AsyncResult<SuspendAccountResult>;
  /**
   * Repositories running as a user, with RLS, over direct Postgres. With
   * `impersonation`, the claims carry `act: { kind: "impersonation", sub, reason }`, which
   * the `audit` and `actor` SQL modules record.
   */
  actingAs(
    userId: string,
    claims?: Omit<SqlClaims, "sub" | "act">,
    impersonation?: ImpersonationOptions,
  ): Db<M, F, E, undefined, B>;
  /**
   * Repositories for the user in a recorded context (`job.context`), with
   * RLS, over direct Postgres: `actingAs` with the context's tenant and
   * `ServerOptions.claimsFor`. A delegated token's `client_id`, `scope`,
   * `authorization_details` and `act` chain go back into the claims, so
   * the work stays as narrow as the token that queued it; `claimsFor`
   * can't set them. A context with a `ticket` runs as the context
   * `options.ticket` or `authorization.tickets.subject` resolves it to.
   * Fails with `forbidden` when the actor is not a user, the `act` chain
   * or delegation is malformed, or the ticket has no resolver or is
   * refused; it never falls back to the recorded actor or `admin()`.
   */
  forContext(
    context: RequestContext,
    options?: ForContextOptions,
  ): AsyncResult<Db<M, F, E, undefined, B>>;
  /** Support sessions; every method fails without `ServerOptions.support`. */
  readonly support: SupportApi;
  /** `options.authorizer`, when the server has one. */
  readonly authorizer: AnyAuthorizer | undefined;
  /** `options.authorization`, when the server has one. */
  readonly authorization: AuthorizationHooks | undefined;
}

export type ServerKeys = keyof BetterServer<AnyModels, AnyFunctions, unknown>;
