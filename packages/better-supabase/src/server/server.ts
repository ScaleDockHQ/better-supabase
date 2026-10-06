import type { JWTClaims, UserClaims } from "@supabase/server";

import { PostgrestClient } from "@supabase/postgrest-js";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { CookieWrite } from "../auth/session.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { EventHub } from "../core/events.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../postgres/pool.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { ActiveSupport, SupportApi, SupportSessions } from "./support.ts";

import { actorOf } from "../auth/actor.ts";
import {
  actClaim,
  type ImpersonationOptions,
  impersonatorClaim,
  userContext,
} from "../auth/impersonation.ts";
import {
  type AuthResolution,
  type AuthState,
  authContext,
  prefetchJwks,
  resolveAuth,
  type ResolveAuthOptions,
} from "../auth/resolve.ts";
import { dbError } from "../core/errors.ts";
import {
  type PostgrestClientLike,
  postgrestExecutor,
} from "../core/postgrest-executor.ts";
import { AsyncResult, ok } from "../core/result.ts";
import { type DbStats, StatsRecorder } from "../core/stats.ts";
import { type BetterSupabaseEnv, loadEnv } from "../env/index.ts";
import {
  deleteAccount,
  type DeleteAccountOptions,
  type DeleteAccountResult,
} from "./delete-account.ts";
import {
  DEFAULT_PIN_MS,
  pinnedUntil,
  primaryCookieWrite,
  type ReplicaState,
  replicaState,
  routedExecutor,
  withPrimaryPin,
} from "./replicas.ts";
import { defaultPrefetchJwks } from "./respond.ts";
import { supportOff } from "./support-off.ts";

export interface ServerOptions {
  /** Defaults to `loadEnv()`. */
  readonly env?: BetterSupabaseEnv;
  /** Enables `ctx.sql` and `actingAs()`. */
  readonly postgres?: BetterPostgres;
  readonly auth?: Omit<ResolveAuthOptions, "env">;
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
   * from a URL slug (`sql.modules.access.activeTenant: 'resolver'`). It becomes
   * `context.tenant` for the `tenant()` plugin, the `better_supabase.tenant`
   * setting over Postgres and the `x-bs-tenant` header over PostgREST, which
   * `current_tenant_id()` reads only while the caller is a member. Async
   * resolvers need `context(request)`; `contextFromResolution` takes
   * `options.tenant` instead.
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
}

export interface ForContextOptions {
  /** Recorded as `act.reason` when the context carries an impersonator. Defaults to `"job"`. */
  readonly reason?: string;
}

/** The header `current_tenant_id()` reads over the Data API. */
export const TENANT_HEADER = "x-bs-tenant";

export interface ServerContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly auth: AuthState<C, P>;
  readonly resolution: AuthResolution<C, P>;
  /**
   * supabase-js client scoped to the caller (RLS applies). Throws in a
   * support session: Realtime, Storage and Auth would act as the admin.
   */
  readonly supabase: SupabaseClient;
  /** Repositories over PostgREST as the caller. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** Repositories over direct Postgres as the caller, when `postgres` is configured. */
  readonly sql: Db<M, F, E, undefined> | undefined;
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
}

export interface BetterServer<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly env: BetterSupabaseEnv;
  /** The definition's events; adapters pass `events.settled()` to `waitUntil`. */
  readonly events: EventHub;
  resolve(
    request: Request,
    options?: { readonly refresh?: boolean; readonly cookies?: boolean },
  ): Promise<AuthResolution<C, P>>;
  /**
   * Resolves auth and binds repositories to the caller. Refreshes an expired
   * cookie session only with `refresh: true`; send `ctx.apply(response)`.
   */
  context(
    request: Request,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P>>;
  /**
   * The context for a resolution from `resolve(request)`, so one resolution
   * can back several contexts without verifying the token again.
   */
  contextFromResolution(
    resolution: AuthResolution<C, P>,
    request: Request,
    options?: Omit<ContextOptions, "refresh">,
  ): ServerContext<M, F, E, C, P>;
  /** The context for an auth state resolved elsewhere (the proxy, a queue message). */
  contextFor(
    auth: AuthState<C, P>,
    options?: ContextOptions,
  ): ServerContext<M, F, E, C, P>;
  /** A stateless supabase-js client for an auth state, optionally with extra request headers. */
  supabaseFor(
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ): SupabaseClient;
  /** Repositories for an auth state (e.g. one resolved by the proxy). */
  dbFor(auth: AuthState, context?: RequestContext): Db<M, F, E, SupabaseClient>;
  /** Service-role repositories. Bypasses RLS; the actor is `service`. */
  admin(context?: RequestContext): Db<M, F, E, SupabaseClient>;
  /**
   * Deletes a user: their objects in `buckets`, then the Auth user, then a
   * `mutation` notice for `auth.users`. Needs the secret key. Access tokens
   * already issued stay valid until they expire.
   */
  deleteAccount(
    userId: string,
    options?: DeleteAccountOptions,
  ): AsyncResult<DeleteAccountResult>;
  /**
   * Repositories running as a user, with RLS, over direct Postgres. With
   * `impersonation`, the claims carry `act: { kind: "impersonation", sub, reason }`, which
   * the `audit` and `actor` SQL modules record.
   */
  actingAs(
    userId: string,
    claims?: Omit<SqlClaims, "sub" | "act">,
    impersonation?: ImpersonationOptions,
  ): Db<M, F, E, undefined>;
  /**
   * Repositories for the user in a recorded context (`job.context`), with
   * RLS, over direct Postgres: `actingAs` with the context's tenant and
   * `ServerOptions.claimsFor`. Fails with `forbidden` when the actor is not a
   * user; it never falls back to `admin()`.
   */
  forContext(
    context: RequestContext,
    options?: ForContextOptions,
  ): AsyncResult<Db<M, F, E, undefined>>;
  /** Support sessions; every method fails without `ServerOptions.support`. */
  readonly support: SupportApi;
}

const STATELESS = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const;

type ServerKeys = keyof BetterServer<AnyModels, AnyFunctions, unknown>;

/**
 * A framework adapter's server: `server` plus the adapter's own methods,
 * without reading the lazy `env` getter. `extra` can't replace a
 * `BetterServer` method.
 */
export function extendServer<R extends object>(
  server: object,
  extra: Omit<R, ServerKeys>,
): R {
  // SAFETY: the descriptors copy every property of server and extra, getters included.
  return Object.defineProperties(
    {},
    {
      ...Object.getOwnPropertyDescriptors(server),
      ...Object.getOwnPropertyDescriptors(extra),
    },
  ) as R;
}

/** `{ ...base, ...extra }` that keeps lazy getters lazy. */
export function withExtra<T extends object, X extends object>(
  base: T,
  extra: X,
): T & X {
  // SAFETY: the descriptors copy every property of base and extra, getters included.
  return Object.defineProperties(
    {},
    {
      ...Object.getOwnPropertyDescriptors(base),
      ...Object.getOwnPropertyDescriptors(extra),
    },
  ) as T & X;
}

/**
 * Server-side entry point for APIs, jobs, MCP servers and framework
 * adapters. Holds the secrets; `betterSupabase` stays isomorphic.
 */
export function createServer<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: ServerOptions = {},
): BetterServer<M, F, E, C, P> {
  let loaded: BetterSupabaseEnv | undefined;
  const env = (): BetterSupabaseEnv => (loaded ??= options.env ?? loadEnv());
  let adminClient: SupabaseClient | undefined;
  let anonClient: SupabaseClient | undefined;

  if (
    (options.prefetchJwks ?? defaultPrefetchJwks()) &&
    options.auth?.jwks === undefined
  ) {
    try {
      void prefetchJwks({ ...options.auth, env: env() });
    } catch {
      // No environment yet (a build step): the first request loads it.
    }
  }

  const secretKey = (): string => {
    const key = env().secretKey;
    if (!key) {
      throw new TypeError("admin() needs SUPABASE_SECRET_KEY; it is not set");
    }
    return key;
  };
  const customFetch = options.fetch ? { fetch: options.fetch } : undefined;
  const sharedGlobal = customFetch ? { global: customFetch } : {};
  const serviceClient = (): SupabaseClient => {
    adminClient ??= createClient(env().url, secretKey(), {
      auth: STATELESS,
      ...sharedGlobal,
    });
    return adminClient;
  };

  const readUrl = (): string | undefined =>
    options.readUrl === false
      ? undefined
      : (options.readUrl?.replace(/\/+$/, "") ?? env().readUrl);

  /** Clients for the primary share the service and anon clients; others don't. */
  const supabaseAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => {
    const custom = Object.keys(headers).length > 0;
    const global = custom
      ? { global: { headers, ...customFetch } }
      : sharedGlobal;
    const shared = !custom && url === env().url;
    switch (auth.kind) {
      case "user":
        // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
        return createClient(url, env().publishableKey, {
          accessToken: () => Promise.resolve(auth.token),
          ...global,
        });
      case "service":
        // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
        return shared
          ? serviceClient()
          : createClient(url, secretKey(), { auth: STATELESS, ...global });
      case "anon":
      case "invalid":
        if (!shared) {
          // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
          return createClient(url, env().publishableKey, {
            auth: STATELESS,
            ...global,
          });
        }
        anonClient ??= createClient(url, env().publishableKey, {
          auth: STATELESS,
          ...sharedGlobal,
        });
        return anonClient;
      default: {
        const exhaustive: never = auth;
        return exhaustive;
      }
    }
  };

  const supabaseFor = (
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => supabaseAt(env().url, auth, headers);

  /**
   * The client queries run on. A user's requests need only PostgREST, so they
   * skip building Realtime, Storage and Auth clients per request; the shared
   * service and anon clients are built once anyway.
   */
  const restAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): PostgrestClientLike => {
    if (auth.kind !== "user") return supabaseAt(url, auth, headers);
    const key = env().publishableKey;
    return new PostgrestClient(
      new URL("rest/v1", url.endsWith("/") ? url : `${url}/`).href,
      {
        headers: {
          ...headers,
          apikey: key,
          Authorization: `Bearer ${auth.token}`,
        },
        ...customFetch,
      },
    );
  };

  /** `$client` stays the full Supabase client, built when first read. */
  const withLazyClient = <T extends object>(
    db: T,
    client: () => SupabaseClient,
  ): T =>
    Object.defineProperty(db, "$client", {
      get: client,
      enumerable: true,
      configurable: true,
    });

  const dbFor = (
    auth: AuthState,
    context: RequestContext = {},
  ): Db<M, F, E, SupabaseClient> => {
    let supabase: SupabaseClient | undefined;
    const rest = restAt(env().url, auth);
    // SAFETY: `$client` is redefined below to return the SupabaseClient.
    const db = betterSupabase.connect(rest, {
      ...authContext(auth),
      ...context,
    }) as Db<M, F, E, SupabaseClient>;
    return withLazyClient(db, () => (supabase ??= supabaseFor(auth)));
  };

  const sqlFor = (
    claims: SqlClaims,
    context: RequestContext,
    stats?: StatsRecorder,
    session?: SessionOptions,
  ): Db<M, F, E, undefined> => {
    if (!options.postgres) {
      throw new TypeError(
        "Direct Postgres access needs createServer(betterSupabase, { postgres: createPostgres() })",
      );
    }
    return betterSupabase.connect(
      session
        ? options.postgres.executorFor(claims, session)
        : options.postgres.executorFor(claims),
      context,
      stats ? { stats } : {},
    );
  };

  /** `ServerOptions.tenant` outside `context()`, where it can't be awaited. */
  const syncTenant = (
    request: Request,
    auth: AuthState,
  ): string | undefined => {
    const tenant = options.tenant?.(request, auth);
    if (tenant !== undefined && typeof tenant !== "string") {
      throw new TypeError(
        "ServerOptions.tenant returned a promise: use context(request), or pass { tenant } to contextFromResolution",
      );
    }
    return tenant;
  };

  const pinMs = options.replicas?.pinMs ?? DEFAULT_PIN_MS;

  if (options.support && !options.postgres) {
    throw new TypeError(
      "Support sessions need createServer(betterSupabase, { postgres: createPostgres(), support })",
    );
  }
  const support = options.support
    ? options.support.create(
        betterSupabase.events,
        options.auth?.claims ?? betterSupabase.claimsSchema,
      )
    : supportOff;

  /**
   * The target's context in a support session. Queries run over direct
   * Postgres with the target's claims plus `act`, read-only unless the
   * session allows writes; nothing reaches Supabase with the admin's token.
   */
  const supportContextFor = (
    resolution: AuthResolution<C, P>,
    active: ActiveSupport,
    parent: StatsRecorder | undefined,
    tenant: string | undefined,
  ): ServerContext<M, F, E, C, P> => {
    const { session, claims } = active;
    const record = (key: string): Record<string, unknown> | undefined => {
      const value = claims[key];
      return typeof value === "object" &&
        value !== null &&
        !Array.isArray(value)
        ? Object.fromEntries(Object.entries(value))
        : undefined;
    };
    const appMetadata = record("app_metadata");
    const userMetadata = record("user_metadata");
    const user: UserClaims = {
      id: session.targetUserId,
      role:
        typeof claims["role"] === "string" ? claims["role"] : "authenticated",
      ...(typeof claims["email"] === "string"
        ? { email: claims["email"] }
        : {}),
      ...(appMetadata ? { appMetadata } : {}),
      ...(userMetadata ? { userMetadata } : {}),
    };
    const auth: AuthState<C, P> = {
      kind: "user",
      token: "",
      // SAFETY: support.current() ran the claims schema over these claims.
      claims: claims as JWTClaims & C,
      user,
      source: "support",
      expiresAt: Math.floor(session.expiresAt.epochMilliseconds / 1000),
    };
    const scope = tenant ?? session.tenant;
    const base = userContext(user, claims);
    const context: RequestContext =
      scope === undefined ? base : { ...base, tenant: scope };
    const sessionOptions: SessionOptions = {
      ...(session.readOnly ? { readOnly: true } : {}),
      ...(scope === undefined
        ? {}
        : { settings: { "better_supabase.tenant": scope } }),
    };
    const recorder = new StatsRecorder(parent);
    // SAFETY: SqlClaims is the JWT payload; claims holds the target's.
    const sqlClaims = claims as SqlClaims;
    const unavailable = (): never => {
      throw new TypeError(
        "ctx.supabase and ctx.db.$client are not available in a support session; ctx.db and ctx.sql run as the target",
      );
    };
    let db: Db<M, F, E, SupabaseClient> | undefined;
    let sql: Db<M, F, E, undefined> | undefined;
    return {
      auth,
      resolution,
      support: active,
      get supabase(): SupabaseClient {
        return unavailable();
      },
      get db() {
        // SAFETY: `$client` is redefined to throw, so no caller gets a client.
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the repositories are the same; only `$client`'s type differs, and it throws.
        db ??= Object.defineProperty(
          sqlFor(sqlClaims, context, recorder, sessionOptions),
          "$client",
          { get: unavailable, enumerable: true, configurable: true },
        ) as unknown as Db<M, F, E, SupabaseClient>;
        return db;
      },
      get sql() {
        sql ??= sqlFor(sqlClaims, context, recorder, sessionOptions);
        return sql;
      },
      replica: undefined,
      stats: () => recorder.snapshot(),
      apply: (response) => resolution.apply(response),
      cookies: () => resolution.cookies,
    };
  };

  /** Clients and repositories are built on first access: most scopes use one of them. */
  const contextFor = (
    resolution: AuthResolution<C, P>,
    requestHeaders: Readonly<Record<string, string>>,
    parent: StatsRecorder | undefined,
    until = 0,
    tenant?: string,
    active?: ActiveSupport,
  ): ServerContext<M, F, E, C, P> => {
    if (active) return supportContextFor(resolution, active, parent, tenant);
    const { auth } = resolution;
    const context: RequestContext =
      tenant === undefined
        ? authContext(auth)
        : { ...authContext(auth), tenant };
    const headers =
      tenant === undefined
        ? requestHeaders
        : { ...requestHeaders, [TENANT_HEADER]: tenant };
    const session: SessionOptions | undefined =
      tenant === undefined
        ? undefined
        : { settings: { "better_supabase.tenant": tenant } };
    const recorder = new StatsRecorder(parent);
    let supabase: SupabaseClient | undefined;
    let db: Db<M, F, E, SupabaseClient> | undefined;
    let sql: Db<M, F, E, undefined> | undefined;
    const sqlClaims: SqlClaims | undefined =
      auth.kind === "user"
        ? auth.claims
        : auth.kind === "anon"
          ? { role: "anon" }
          : undefined;
    const client = (): SupabaseClient =>
      (supabase ??= supabaseFor(auth, headers));
    let replica: ReplicaState | undefined;
    const replicaUrl = (): string | undefined => {
      const url = readUrl();
      if (url) replica ??= replicaState(until);
      return url;
    };
    return {
      auth,
      resolution,
      get supabase() {
        return client();
      },
      get db() {
        if (db) return db;
        const url = replicaUrl();
        const { maxUrlLength } = betterSupabase.options;
        const executorOptions =
          maxUrlLength === undefined ? {} : { maxUrlLength };
        const rest: PostgrestClientLike =
          supabase ?? restAt(env().url, auth, headers);
        const connected = betterSupabase.connect(rest, context, {
          stats: recorder,
          ...(url && replica
            ? {
                executor: routedExecutor(
                  postgrestExecutor(rest, executorOptions),
                  postgrestExecutor(
                    restAt(url, auth, headers),
                    executorOptions,
                  ),
                  replica,
                ),
              }
            : {}),
        });
        // SAFETY: `$client` is redefined to return the SupabaseClient.
        db = withLazyClient(connected as Db<M, F, E, SupabaseClient>, client);
        return db;
      },
      get replica() {
        replicaUrl();
        return replica;
      },
      get sql() {
        if (!options.postgres || !sqlClaims) return;
        sql ??= sqlFor(sqlClaims, context, recorder, session);
        return sql;
      },
      stats: () => recorder.snapshot(),
      apply: (response) =>
        withPrimaryPin(resolution.apply(response), replica, pinMs),
      cookies: () => {
        const pin = primaryCookieWrite(replica, pinMs);
        return pin ? [...resolution.cookies, pin] : resolution.cookies;
      },
    };
  };

  const fromResolution = (
    resolution: AuthResolution<C, P>,
    request: Request,
    contextOptions: ContextOptions,
    tenant: string | undefined,
  ): ServerContext<M, F, E, C, P> =>
    contextFor(
      resolution,
      options.headers?.(request) ?? {},
      contextOptions.stats,
      contextOptions.pinnedUntil ??
        (readUrl() ? pinnedUntil(resolution.requestCookies) : 0),
      tenant,
      contextOptions.support,
    );

  const resolve = async (
    request: Request,
    resolveOptions: {
      readonly refresh?: boolean;
      readonly cookies?: boolean;
    } = {},
  ): Promise<AuthResolution<C, P>> => {
    const claims = options.auth?.claims ?? betterSupabase.claimsSchema;
    const userMetadata = betterSupabase.userMetadataSchema;
    const resolved = await resolveAuth(request, {
      logger: betterSupabase.events.logger,
      ...options.auth,
      ...(claims ? { claims } : {}),
      ...(userMetadata ? { userMetadata } : {}),
      env: env(),
      ...(resolveOptions.refresh === undefined
        ? {}
        : { refresh: resolveOptions.refresh }),
      ...(resolveOptions.cookies === undefined
        ? {}
        : { cookies: resolveOptions.cookies }),
      onRefresh: (event) => {
        options.auth?.onRefresh?.(event);
        betterSupabase.events.emit("refresh", event);
      },
    });
    // The claims schema's output is merged into every verified user's claims,
    // and the userMetadata schema's output is the profile.
    // SAFETY: the resolver ran the claims and userMetadata schemas, so resolved
    // has their output types.
    const resolution = resolved as AuthResolution<C, P>;
    if (betterSupabase.events.has("auth")) {
      const { auth } = resolution;
      betterSupabase.events.emit("auth", {
        source:
          auth.kind === "user"
            ? auth.source === "cookie"
              ? "cookie"
              : "bearer"
            : auth.kind === "service"
              ? "bearer"
              : "none",
        ok: auth.kind !== "invalid",
        ...(auth.kind === "user"
          ? { userId: auth.user.id, rawSource: auth.source }
          : {}),
        ...(auth.kind === "anon" || auth.kind === "invalid"
          ? { reason: auth.reason }
          : {}),
      });
    }
    return resolution;
  };

  const server: BetterServer<M, F, E, C, P> = {
    get env() {
      return env();
    },
    events: betterSupabase.events,
    resolve,
    supabaseFor,
    dbFor,
    contextFor: (auth, contextOptions = {}) =>
      contextFor(
        {
          auth,
          cookies: [],
          headers: {},
          requestCookies: [],
          apply: (response) => response,
        },
        {},
        contextOptions.stats,
        contextOptions.pinnedUntil,
        contextOptions.tenant,
        contextOptions.support,
      ),
    async context(request, contextOptions = {}) {
      const resolution = await resolve(request, {
        refresh: contextOptions.refresh ?? false,
        ...(contextOptions.cookies === undefined
          ? {}
          : { cookies: contextOptions.cookies }),
      });
      const [tenant, active] = await Promise.all([
        contextOptions.tenant ?? options.tenant?.(request, resolution.auth),
        contextOptions.support ?? support.current(request, resolution.auth),
      ]);
      return fromResolution(
        resolution,
        request,
        active ? { ...contextOptions, support: active } : contextOptions,
        tenant,
      );
    },
    contextFromResolution: (resolution, request, contextOptions = {}) =>
      fromResolution(
        resolution,
        request,
        contextOptions,
        contextOptions.tenant ?? syncTenant(request, resolution.auth),
      ),
    admin: (context = {}) =>
      betterSupabase.connect(serviceClient(), {
        actor: { id: "service", kind: "service", role: "service_role" },
        claims: { role: "service_role" },
        ...context,
      }),
    support,
    deleteAccount: (userId, deleteOptions) =>
      deleteAccount(betterSupabase, serviceClient, userId, deleteOptions),
    actingAs: (userId, claims = {}, impersonation) => {
      const full: SqlClaims = {
        role: "authenticated",
        ...claims,
        sub: userId,
        ...(impersonation ? { act: actClaim(impersonation) } : {}),
      };
      return sqlFor(full, {
        actor: {
          id: userId,
          kind: "user",
          role: full.role ?? "authenticated",
          ...(impersonation ? { impersonator: impersonation.actor } : {}),
        },
        claims: full,
      });
    },
    forContext: (context, forOptions = {}) => {
      const { actor, tenant } = context;
      if (actor?.kind !== "user") {
        return AsyncResult.err(
          dbError(
            "forbidden",
            `forContext needs a user actor, got ${actor ? actor.kind : "none"}: use admin() for service work`,
          ),
        );
      }
      if (!options.postgres) {
        return AsyncResult.err(
          dbError(
            "invalid_request",
            "Direct Postgres access needs createServer(betterSupabase, { postgres: createPostgres() })",
          ),
        );
      }
      const recorded = actorOf(context.claims ?? {});
      if (!recorded.ok) {
        return AsyncResult.err(
          dbError("forbidden", "forContext got an invalid act claim"),
        );
      }
      const support =
        recorded.actor?.kind === "support" ? recorded.actor : undefined;
      const impersonator = support?.id ?? actor.impersonator;
      return AsyncResult.from(async () => {
        const extra = (await options.claimsFor?.(actor.id, context)) ?? {};
        const claims: SqlClaims = {
          ...extra,
          role: "authenticated",
          sub: actor.id,
          ...(tenant === undefined ? {} : { tenant_id: tenant }),
          ...(support
            ? { act: impersonatorClaim(support) }
            : actor.impersonator
              ? {
                  act: actClaim({
                    actor: actor.impersonator,
                    reason: forOptions.reason ?? "job",
                  }),
                }
              : {}),
        };
        const session: SessionOptions = {
          ...(support?.readOnly ? { readOnly: true } : {}),
          ...(tenant === undefined
            ? {}
            : { settings: { "better_supabase.tenant": tenant } }),
        };
        return ok(
          sqlFor(
            claims,
            {
              actor: {
                id: actor.id,
                kind: "user",
                role: "authenticated",
                ...(impersonator ? { impersonator } : {}),
              },
              claims,
              ...(tenant === undefined ? {} : { tenant }),
            },
            undefined,
            Object.keys(session).length === 0 ? undefined : session,
          ),
        );
      });
    },
  };
  return server;
}
