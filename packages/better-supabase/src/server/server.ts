import type { JWTClaims, UserClaims } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

import { getEnv, pipeline, seedContext } from "@supabase/middleware";
import { createClient } from "@supabase/supabase-js";

import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { SessionEncoding } from "../auth/session.ts";
import type {
  DelegationPermissions,
  TicketSubject,
} from "../core/contracts/authorization-hooks.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { PostgrestClientLike } from "../core/postgrest-executor.ts";
import type { Db } from "../core/repository-types.ts";
import type { Result } from "../core/result.ts";
import type { BetterSupabaseEnv, EnvSource } from "../env/index.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type { SessionOptions, SqlClaims } from "../postgres/pool.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { StorageApi } from "../storage/storage-api.ts";
import type { CallState, ServerCore } from "./entries/core.ts";
import type { ReplicaState } from "./replicas.ts";
import type { RequestIds } from "./request-ids.ts";
import type {
  AdminDb,
  BetterServer,
  ContextOptions,
  ServerContext,
  ServerKeys,
  ServerOptions,
} from "./server-types.ts";
import type { ActiveSupport } from "./support.ts";

import { authContext } from "../auth/context.ts";
import {
  contextClaims,
  delegatedClaims,
  narrowCap,
} from "../auth/delegation.ts";
import { actClaim, userContext } from "../auth/impersonation.ts";
import { prefetchJwks, resolveAuth } from "../auth/resolve.ts";
import { sessionCookieName } from "../auth/session.ts";
import { hooksApiProblem } from "../core/contracts/authorization-hooks.ts";
import { dbError } from "../core/errors.ts";
import { postgrestExecutor } from "../core/postgrest-executor.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { StatsRecorder } from "../core/stats.ts";
import { credentialProviderOf } from "../credentials/provider.ts";
import { loadEnv } from "../env/index.ts";
import { serverAudit } from "./audit.ts";
import { createClients } from "./clients.ts";
import { deleteAccount } from "./delete-account.ts";
import { withServerContext } from "./entries/context.ts";
import { CALL, callOf, registerCore, shareCore } from "./entries/core.ts";
import { withSession } from "./entries/session.ts";
import { withSupport } from "./entries/support.ts";
import { withTenant } from "./entries/tenant.ts";
import { liteBackend } from "./lite.ts";
import { refusingExecutor } from "./refusing-executor.ts";
import {
  DEFAULT_PIN_MS,
  pinnedUntil,
  primaryCookieWrite,
  replicaState,
  routedExecutor,
  withPrimaryPin,
} from "./replicas.ts";
import { requestIdPolicy, sessionWith } from "./request-ids.ts";
import { defaultPrefetchJwks } from "./respond.ts";
import { TENANT_HEADER } from "./server-types.ts";
import { supportOff } from "./support-off.ts";
import { supportStorage } from "./support-storage.ts";
import { endSessions, suspendAccount } from "./suspend-account.ts";

/** The header `better_supabase.acting_member()` reads for a service caller. */
const ACTOR_HEADER = "x-bsb-actor";

/** The environment as `getEnv` resolves it, one variable at a time. */
const RUNTIME_ENV: EnvSource = new Proxy<EnvSource>(
  {},
  {
    get: (_target, key) => (typeof key === "string" ? getEnv(key) : undefined),
  },
);

/**
 * `options.env` as given when it is loaded already, parsed when it is a
 * variable map (never merged with the runtime's), else the runtime's.
 */
function envOf(env: ServerOptions["env"]): BetterSupabaseEnv {
  if (env === undefined) {
    return loadEnv(RUNTIME_ENV);
  }

  return isLoadedEnv(env) ? env : loadEnv(env);
}

/**
 * An `EnvSource` holds only strings, so a `URL` in `jwksUrl` means a loaded
 * env.
 */
function isLoadedEnv(
  env: BetterSupabaseEnv | EnvSource,
): env is BetterSupabaseEnv {
  return env.jwksUrl instanceof URL;
}

const needsPostgres = (method: string) =>
  dbError(
    "invalid_request",
    `${method} needs createServer(betterSupabase, { postgres: createPostgres() })`,
  );

/**
 * A framework adapter's server: `server` plus the adapter's own methods,
 * without reading the lazy `env` getter. `extra` can't replace a `BetterServer`
 * method.
 */
export function extendServer<R extends object>(
  server: object,
  extra: Omit<R, ServerKeys>,
): R {
  const extended = Object.defineProperties(
    {},
    {
      ...Object.getOwnPropertyDescriptors(server),
      ...Object.getOwnPropertyDescriptors(extra),
    },
  );

  shareCore(server, extended);

  // SAFETY: the descriptors copy every property of server and extra, getters included.
  return extended as R;
}

/**
 * Server-side entry point for APIs, jobs, MCP servers and framework adapters.
 * Holds the secrets; `betterSupabase` stays isomorphic.
 */
export function createServer<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: ServerOptions = {},
): BetterServer<M, F, E, C, P, B> {
  const credentials =
    options.credentials === undefined
      ? {}
      : { credentials: credentialProviderOf(options.credentials) };

  let loaded: BetterSupabaseEnv | undefined;

  const env = (): BetterSupabaseEnv => (loaded ??= envOf(options.env));

  const lite = liteBackend(options, env);

  if (
    lite === undefined &&
    (options.prefetchJwks ?? defaultPrefetchJwks()) &&
    options.auth?.jwks === undefined
  ) {
    try {
      void prefetchJwks({ ...options.auth, env: env() });
    } catch {
      // No environment yet (a build step): the first request loads it.
    }
  }

  const {
    executorOptions,
    tunedExecutor,
    serviceClient,
    readUrl,
    apiKeyClient,
    supabaseFor,
    restAt,
  } = createClients({
    options,
    env,
    definitionExecutor: betterSupabase.executorOptions(),
    lite,
    createClient,
  });

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
  ): Db<M, F, E, SupabaseClient, B> => {
    let supabase: SupabaseClient | undefined;
    const rest = restAt(env().url, auth);

    // `db.$storage` and `db.$buckets` build the full client on first use.
    const storage: StorageApi = {
      from: (bucket) => (supabase ??= supabaseFor(auth)).storage.from(bucket),
    };

    // SAFETY: `$client` is redefined below to return the SupabaseClient.
    const db = betterSupabase.connect(
      rest,
      { ...authContext(auth), ...context },
      auth.kind === "invalid"
        ? { executor: refusingExecutor(auth.error), storage }
        : tunedExecutor
          ? { executor: postgrestExecutor(rest, executorOptions), storage }
          : { storage },
    ) as Db<M, F, E, SupabaseClient, B>;

    return withLazyClient(db, () => (supabase ??= supabaseFor(auth)));
  };

  const sqlFor = (
    claims: SqlClaims,
    context: RequestContext,
    stats?: StatsRecorder,
    session?: SessionOptions,
    storage?: StorageApi,
  ): Db<M, F, E, undefined, B> => {
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
      { ...(stats ? { stats } : {}), ...(storage ? { storage } : {}) },
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
  const idPolicy = requestIdPolicy(options.requestIds);

  if (options.support && !options.postgres) {
    throw new TypeError(
      "Support sessions need createServer(betterSupabase, { postgres: createPostgres(), support })",
    );
  }

  const hooksProblem =
    options.authorization === undefined
      ? undefined
      : hooksApiProblem(options.authorization);

  if (hooksProblem !== undefined) {
    throw new TypeError(hooksProblem);
  }

  const audit = serverAudit(betterSupabase, options.audit);

  const support = options.support
    ? options.support.create(
        betterSupabase.events,
        options.auth?.claims ?? betterSupabase.claimsSchema,
        betterSupabase.temporal,
        options.authorization,
      )
    : supportOff;

  /**
   * The target's context in a support session. Queries run over direct Postgres
   * with the target's claims plus `act`, read-only unless the session allows
   * writes; nothing reaches Supabase with the admin's token.
   */
  const supportContextFor = (
    resolution: AuthResolution<C, P>,
    active: ActiveSupport,
    parent: StatsRecorder | undefined,
    tenant: string | undefined,
    ids: RequestIds,
  ): ServerContext<M, F, E, C, P, B> => {
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

    const sessionOptions = sessionWith(ids, scope, session.readOnly);
    const recorder = new StatsRecorder(parent);
    // SAFETY: SqlClaims is the JWT payload; claims holds the target's.
    const sqlClaims = claims as SqlClaims;

    const unavailable = (): never => {
      throw new TypeError(
        "ctx.supabase and ctx.db.$client are not available in a support session; ctx.db and ctx.sql run as the target",
      );
    };

    let db: Db<M, F, E, SupabaseClient, B> | undefined;
    let sql: Db<M, F, E, undefined, B> | undefined;
    let storage: StorageApi | undefined;

    const targetStorage = (): StorageApi => {
      const postgres = options.postgres;

      if (!postgres) {
        throw new TypeError(
          "Support sessions need createServer(betterSupabase, { postgres: createPostgres(), support })",
        );
      }

      let asTarget: SqlClient | undefined;

      const target = (): SqlClient =>
        (asTarget ??= postgres.asUser(sqlClaims, sessionOptions));

      storage ??= supportStorage({
        admin: { from: (bucket) => serviceClient().storage.from(bucket) },
        sql: {
          queryRaw: <T>(text: string, params?: unknown[]) =>
            target().queryRaw<T>(text, params),
          transaction: <T>(fn: (client: SqlClient) => Promise<T>) =>
            target().transaction?.(fn) ??
            Promise.reject(
              new TypeError("The target's SQL client has no transaction"),
            ),
        },
        adminSql: postgres.admin,
        session,
        readOnly: session.readOnly,
      });

      return storage;
    };

    return {
      ...credentials,
      ...ids,
      auth,
      resolution,
      support: active,
      get storage() {
        return targetStorage();
      },
      get supabase(): SupabaseClient {
        return unavailable();
      },
      get db() {
        // SAFETY: `$client` is redefined to throw, so no caller gets a client.
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the repositories are the same; only `$client`'s type differs, and it throws.
        db ??= Object.defineProperty(
          sqlFor(sqlClaims, context, recorder, sessionOptions, targetStorage()),
          "$client",
          { get: unavailable, enumerable: true, configurable: true },
        ) as unknown as Db<M, F, E, SupabaseClient, B>;

        return db;
      },
      get sql() {
        sql ??= sqlFor(
          sqlClaims,
          context,
          recorder,
          sessionOptions,
          targetStorage(),
        );

        return sql;
      },
      replica: undefined,
      stats: () => recorder.snapshot(),
      apply: (response) => resolution.apply(response),
      cookies: () => resolution.cookies,
    };
  };

  /**
   * An API key's context. There is no JWT for PostgREST, so `ctx.db` and
   * `ctx.sql` run over direct Postgres with the key's synthesized claims,
   * scoped to its organization unless the tenant option names another.
   */
  const apiKeyContextFor = (
    resolution: AuthResolution<C, P>,
    auth: Extract<AuthState, { kind: "apiKey" }>,
    parent: StatsRecorder | undefined,
    tenant: string | undefined,
    ids: RequestIds,
  ): ServerContext<M, F, E, C, P, B> => {
    const scope = tenant ?? auth.organizationId;
    const base = authContext(auth);

    const context: RequestContext =
      scope === undefined ? base : { ...base, tenant: scope };

    const session = sessionWith(ids, scope);
    const recorder = new StatsRecorder(parent);
    let db: Db<M, F, E, SupabaseClient, B> | undefined;
    let sql: Db<M, F, E, undefined, B> | undefined;

    return {
      ...credentials,
      ...ids,
      auth: resolution.auth,
      resolution,
      get supabase(): SupabaseClient {
        return apiKeyClient();
      },
      get db() {
        // SAFETY: `$client` is redefined to throw, so no caller gets a client.
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the repositories are the same; only `$client`'s type differs, and it throws.
        db ??= Object.defineProperty(
          sqlFor(auth.claims, context, recorder, session),
          "$client",
          { get: apiKeyClient, enumerable: true, configurable: true },
        ) as unknown as Db<M, F, E, SupabaseClient, B>;

        return db;
      },
      get sql() {
        sql ??= sqlFor(auth.claims, context, recorder, session);

        return sql;
      },
      replica: undefined,
      stats: () => recorder.snapshot(),
      apply: (response) => resolution.apply(response),
      cookies: () => resolution.cookies,
    };
  };

  /**
   * Clients and repositories are built on first access: most scopes use one of
   * them.
   */
  const contextFor = (
    resolution: AuthResolution<C, P>,
    requestHeaders: Readonly<Record<string, string>>,
    parent: StatsRecorder | undefined,
    until = 0,
    tenant?: string,
    active?: ActiveSupport,
    ids: RequestIds = {},
  ): ServerContext<M, F, E, C, P, B> => {
    if (active) {
      return supportContextFor(resolution, active, parent, tenant, ids);
    }

    const { auth } = resolution;

    if (auth.kind === "apiKey") {
      return apiKeyContextFor(resolution, auth, parent, tenant, ids);
    }

    const context: RequestContext =
      tenant === undefined
        ? authContext(auth)
        : { ...authContext(auth), tenant };

    const clientHeaders =
      tenant === undefined
        ? requestHeaders
        : { ...requestHeaders, [TENANT_HEADER]: tenant };

    const headers = { ...idPolicy.headers(ids), ...clientHeaders };
    const sharesClient = auth.kind !== "user";
    const session = sessionWith(ids, tenant);
    const recorder = new StatsRecorder(parent);
    let supabase: SupabaseClient | undefined;
    let db: Db<M, F, E, SupabaseClient, B> | undefined;
    let sql: Db<M, F, E, undefined, B> | undefined;

    const sqlClaims: SqlClaims | undefined =
      auth.kind === "user"
        ? auth.claims
        : auth.kind === "anon"
          ? { role: "anon" }
          : undefined;

    const client = (): SupabaseClient =>
      (supabase ??= supabaseFor(auth, sharesClient ? clientHeaders : headers));

    let replica: ReplicaState | undefined;

    const replicaUrl = (): string | undefined => {
      const url = readUrl();

      if (url) {
        replica ??= replicaState(until);
      }

      return url;
    };

    return {
      ...credentials,
      ...ids,
      auth,
      resolution,
      get supabase() {
        return client();
      },
      get db() {
        if (db) {
          return db;
        }

        const url = replicaUrl();

        const rest: PostgrestClientLike =
          (sharesClient ? undefined : supabase) ??
          restAt(env().url, auth, headers);

        const connected = betterSupabase.connect(rest, context, {
          stats: recorder,
          storage: { from: (bucket) => client().storage.from(bucket) },
          ...(auth.kind === "invalid"
            ? { executor: refusingExecutor(auth.error) }
            : url && replica
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
              : tunedExecutor
                ? { executor: postgrestExecutor(rest, executorOptions) }
                : {}),
        });

        // SAFETY: `$client` is redefined to return the SupabaseClient.
        db = withLazyClient(
          connected as Db<M, F, E, SupabaseClient, B>,
          client,
        );

        return db;
      },
      get replica() {
        replicaUrl();

        return replica;
      },
      get sql() {
        if (!options.postgres || !sqlClaims) {
          return;
        }

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
  ): ServerContext<M, F, E, C, P, B> =>
    contextFor(
      resolution,
      options.headers?.(request) ?? {},
      contextOptions.stats,
      contextOptions.pinnedUntil ??
        (readUrl() ? pinnedUntil(resolution.requestCookies) : 0),
      tenant,
      contextOptions.support,
      idPolicy.forRequest(request, contextOptions),
    );

  const resolve = async (
    request: Request,
    resolveOptions: {
      readonly refresh?: boolean;
      readonly cookies?: boolean;
      readonly encode?: SessionEncoding;
      readonly checkSession?: boolean;
    } = {},
  ): Promise<AuthResolution<C, P>> => {
    const claims = options.auth?.claims ?? betterSupabase.claimsSchema;
    const userMetadata = betterSupabase.userMetadataSchema;

    const resolved = await resolveAuth(request, {
      logger: betterSupabase.events.logger,
      ...(lite ? lite.auth() : options.auth),
      ...(claims ? { claims } : {}),
      ...(userMetadata ? { userMetadata } : {}),
      env: env(),
      ...(resolveOptions.refresh === undefined
        ? {}
        : { refresh: resolveOptions.refresh }),
      ...(resolveOptions.cookies === undefined
        ? {}
        : { cookies: resolveOptions.cookies }),
      ...(resolveOptions.checkSession ? { checkSession: true } : {}),
      ...(resolveOptions.encode === undefined
        ? {}
        : {
            cookie: { ...options.auth?.cookie, encode: resolveOptions.encode },
          }),
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
            : auth.kind === "service" || auth.kind === "apiKey"
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

  /**
   * One context per request and `refresh`/`cookies` pair: Server Components ask
   * repeatedly.
   */
  const contextMemo = new WeakMap<
    Request,
    Map<string, Promise<ServerContext<M, F, E, C, P, B>>>
  >();

  const server: BetterServer<M, F, E, C, P, B> = {
    get env() {
      return env();
    },
    events: betterSupabase.events,
    authorizer: options.authorizer,
    authorization: options.authorization,
    resolve,
    supabaseFor,
    dbFor: (auth, context, dbOptions) =>
      dbOptions?.support
        ? supportContextFor(
            {
              // SAFETY: a support context only reads `auth` back for ctx.auth.
              auth: auth as AuthState<C, P>,
              cookies: [],
              headers: {},
              requestCookies: [],
              apply: (response) => response,
            },
            dbOptions.support,
            undefined,
            context?.tenant,
            {},
          ).db
        : dbFor(auth, context),
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
        idPolicy.forRequest(undefined, contextOptions),
      ),
    context(request, contextOptions = {}) {
      const { refresh, cookies, ...rest } = contextOptions;

      const key =
        Object.keys(rest).length === 0
          ? `${String(refresh ?? false)}:${String(cookies ?? true)}`
          : undefined;

      let byOptions = key ? contextMemo.get(request) : undefined;
      const known = key ? byOptions?.get(key) : undefined;

      if (known) {
        return known;
      }

      const resolving = (async () => {
        const call: CallState = { options: contextOptions };
        await fold(request, { ...seedContext(), [CALL]: call });

        // SAFETY: the fold's terminal stored this call's ServerContext.
        return call.context as ServerContext<M, F, E, C, P, B>;
      })();

      if (key) {
        if (!byOptions) {
          byOptions = new Map();
          contextMemo.set(request, byOptions);
        }

        const memo = byOptions;
        memo.set(key, resolving);
        resolving.catch(() => {
          if (memo.get(key) === resolving) {
            memo.delete(key);
          }
        });
      }

      return resolving;
    },
    contextFromResolution: (resolution, request, contextOptions = {}) =>
      fromResolution(
        resolution,
        request,
        contextOptions,
        contextOptions.tenant ?? syncTenant(request, resolution.auth),
      ),
    admin: (context = {}, adminOptions = {}) => {
      // `as` names the member the write is for: the `x-bsb-actor` header makes
      // `acting_member()` return it, for audit entries and `set_actor()`.
      const client =
        adminOptions.as === undefined
          ? serviceClient()
          : supabaseFor(
              { kind: "service", keyName: "secret" },
              { [ACTOR_HEADER]: adminOptions.as },
            );

      const db = betterSupabase.connect(
        client,
        {
          actor: { id: "service", kind: "service", role: "service_role" },
          claims: { role: "service_role" },
          ...context,
        },
        tunedExecutor
          ? { executor: postgrestExecutor(client, executorOptions) }
          : {},
      );

      // SAFETY: `$authAdmin` is the one property AdminDb adds to Db.
      return Object.defineProperty(db, "$authAdmin", {
        get: () => client.auth.admin,
      }) as AdminDb<M, F, E, B>;
    },
    support,
    deleteAccount: (userId, deleteOptions) =>
      deleteAccount(betterSupabase, serviceClient, userId, {
        ...(options.postgres ? { sql: options.postgres.admin } : {}),
        ...deleteOptions,
      }).map((deleted) => {
        audit.account("account.deleted", userId, { removed: deleted.removed });

        return deleted;
      }),
    endSessions: (userId) =>
      options.postgres
        ? endSessions(options.postgres.admin, userId).map((ended) => {
            audit.account("account.sessions_ended", userId, {
              ended: ended.ended,
            });

            return ended;
          })
        : AsyncResult.err(needsPostgres("endSessions")),
    suspendAccount: (userId, suspendOptions) =>
      options.postgres
        ? suspendAccount(
            serviceClient,
            options.postgres.admin,
            userId,
            suspendOptions,
          ).map((suspended) => {
            audit.account(
              suspended.suspended ? "account.suspended" : "account.unsuspended",
              userId,
              {
                ended: suspended.ended,
                ...(suspendOptions.duration === undefined
                  ? {}
                  : { duration: suspendOptions.duration }),
              },
            );

            return suspended;
          })
        : AsyncResult.err(needsPostgres("suspendAccount")),
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
    forContext: (context, forOptions = {}) =>
      AsyncResult.from(async () => {
        const subject = await ticketSubject(
          context,
          forOptions.ticket ?? options.authorization?.tickets?.subject,
        );

        if (!subject.ok) {
          return subject;
        }

        const target = subject.data;
        const { tenant } = target;
        const checked = contextClaims(target);

        if (!checked.ok) {
          return err(dbError("forbidden", checked.message));
        }

        if (!options.postgres) {
          return err(
            dbError(
              "invalid_request",
              "Direct Postgres access needs createServer(betterSupabase, { postgres: createPostgres() })",
            ),
          );
        }

        const userId = checked.claims.sub;
        const extra = (await options.claimsFor?.(userId, target)) ?? {};

        const permissions = narrowCap(
          await delegationCap(
            target,
            userId,
            options.authorization?.delegation?.permissions,
          ),
          forOptions.permissions,
        );

        const built = contextClaims(target, {
          extra,
          ...(forOptions.reason === undefined
            ? {}
            : { reason: forOptions.reason }),
          ...(permissions === undefined ? {} : { permissions }),
        });

        if (!built.ok) {
          return err(dbError("forbidden", built.message));
        }

        const { claims, impersonator, readOnly } = built;
        const session = sessionWith({}, tenant, readOnly);

        return ok(
          sqlFor(
            claims,
            {
              actor: {
                id: userId,
                kind: "user",
                role: "authenticated",
                ...(impersonator ? { impersonator } : {}),
              },
              claims,
              ...(tenant === undefined ? {} : { tenant }),
            },
            undefined,
            session,
          ),
        );
      }),
  };

  const core: ServerCore<M, F, E, C, P, B> = {
    events: betterSupabase.events,
    pinMs,
    resolve,
    sessionCookie: () =>
      options.auth?.cookie?.name ?? sessionCookieName(env().url),
    tenant: (request, auth) => options.tenant?.(request, auth),
    support: (request, auth) => support.current(request, auth),
    context: (resolution, request, contextOptions, tenant) =>
      fromResolution(resolution, request, contextOptions, tenant),
  };

  registerCore(server, core);

  const fold = pipeline(
    [
      withSession(core),
      withTenant(core),
      withSupport(core),
      withServerContext(core),
    ] as const,
    (_request, ctx) => {
      const call = callOf(ctx);

      if (call) {
        call.context = ctx.bsb;
      }

      return Promise.resolve(new Response(null, { status: 204 }));
    },
  );

  return server;
}

/**
 * The permission keys the provider's `delegation.permissions` hook grants a
 * delegated context, `undefined` for a context that is not delegated or without
 * the hook. A throw or an answer that is not a list of strings grants nothing.
 */
async function delegationCap(
  context: RequestContext,
  userId: string,
  permissions: DelegationPermissions | undefined,
): Promise<readonly string[] | undefined> {
  if (permissions === undefined) {
    return undefined;
  }

  const delegated = delegatedClaims(context.claims ?? {});

  if (!delegated.ok || delegated.delegation === undefined) {
    return undefined;
  }

  const { client_id, scope, authorization_details } = delegated.delegation;

  try {
    const keys: unknown = await permissions({
      userId,
      ...(context.tenant === undefined ? {} : { tenant: context.tenant }),
      ...(client_id === undefined ? {} : { clientId: client_id }),
      scopes: scope === undefined ? [] : scope.split(" "),
      ...(authorization_details === undefined
        ? {}
        : { authorizationDetails: authorization_details }),
    });

    return Array.isArray(keys) &&
      keys.every((key): key is string => typeof key === "string")
      ? keys
      : [];
  } catch {
    return [];
  }
}

/**
 * The context `forContext` runs as: `context` itself, or for a context with a
 * ticket, the context `resolve` returns for it. A ticket without a resolver, a
 * `null` answer and a throw are `forbidden`; none of them fall back to the
 * recorded actor.
 */
async function ticketSubject(
  context: RequestContext,
  resolve: TicketSubject | undefined,
): Promise<Result<RequestContext>> {
  const ticket = context["ticket"];

  if (ticket === undefined) {
    return ok(context);
  }

  if (typeof ticket !== "string" || ticket === "") {
    return err(dbError("forbidden", "forContext got an invalid ticket"));
  }

  if (resolve === undefined) {
    return err(
      dbError(
        "forbidden",
        "forContext got a ticket but no ticket resolver: pass { ticket } or authorization.tickets.subject",
      ),
    );
  }

  let resolved: unknown;

  try {
    resolved = await resolve(ticket);
  } catch {
    resolved = null;
  }

  if (typeof resolved !== "object" || resolved === null) {
    return err(dbError("forbidden", "The ticket resolver refused the ticket"));
  }

  // SAFETY: TicketSubject returns a RequestContext or null; null and non-objects were refused above.
  return ok(resolved as RequestContext);
}
