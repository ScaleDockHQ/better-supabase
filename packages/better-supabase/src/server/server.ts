import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { AsyncResult } from "../core/result.ts";
import type { Postgres, SqlClaims } from "../postgres/pool.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { actClaim, type ImpersonationOptions } from "../auth/impersonation.ts";
import {
  type AuthResolution,
  type AuthState,
  authContext,
  resolveAuth,
  type ResolveAuthOptions,
} from "../auth/resolve.ts";
import { postgrestExecutor } from "../core/postgrest-executor.ts";
import { type DbStats, StatsRecorder } from "../core/stats.ts";
import { type BetterSupabaseEnv, loadEnv } from "../env/index.ts";
import { postgresExecutor } from "../postgres/executor.ts";
import {
  deleteAccount,
  type DeleteAccountOptions,
  type DeleteAccountResult,
} from "./delete-account.ts";
import {
  pinnedUntil,
  type ReplicaState,
  replicaState,
  routedExecutor,
} from "./replicas.ts";

export interface ServerOptions {
  /** Defaults to `loadEnv()`. */
  readonly env?: BetterSupabaseEnv;
  /** Enables `ctx.sql` and `actingAs()`. */
  readonly postgres?: Postgres;
  readonly auth?: Omit<ResolveAuthOptions, "env">;
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
  readonly replicas?: {
    /** How long the next requests read from the primary after a write. Defaults to 5 s. */
    readonly pinMs?: number;
  };
}

export interface ServerContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly auth: AuthState<C, P>;
  readonly resolution: AuthResolution<C, P>;
  /** supabase-js client scoped to the caller (RLS applies). */
  readonly supabase: SupabaseClient;
  /** Repositories over PostgREST as the caller. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** Repositories over direct Postgres as the caller, when `postgres` is configured. */
  readonly sql: Db<M, F, E, undefined> | undefined;
  /** Calls, waves, tables and time for `db` and `sql` together. */
  stats(): DbStats;
  /** Where `db` reads go, when a read URL is configured. */
  readonly replica: ReplicaState | undefined;
}

export interface ContextOptions {
  readonly refresh?: boolean;
  /** Epoch ms until which `db` reads from the primary (the `bs-primary-until` cookie). */
  readonly pinnedUntil?: number;
  /** Also records this context's calls into a request-wide recorder. */
  readonly stats?: StatsRecorder;
}

export interface BetterServer<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly env: BetterSupabaseEnv;
  resolve(
    request: Request,
    options?: { readonly refresh?: boolean },
  ): Promise<AuthResolution<C, P>>;
  /**
   * Resolves auth and binds repositories to the caller. Refreshes an expired
   * cookie session only with `refresh: true`; send `ctx.resolution.apply(response)`.
   */
  context(
    request: Request,
    options?: ContextOptions,
  ): Promise<ServerContext<M, F, E, C, P>>;
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
   * `impersonation`, the claims carry `act: { sub: actor, reason }`, which
   * the `audit` and `actor` SQL kit modules record.
   */
  actingAs(
    userId: string,
    claims?: Omit<SqlClaims, "sub" | "act">,
    impersonation?: ImpersonationOptions,
  ): Db<M, F, E, undefined>;
}

const STATELESS = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const;

type ServerKeys = keyof BetterServer<AnyModels, AnyFunctions, unknown>;

/** `{ ...server, ...extra }` without reading the lazy `env` getter. */
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
 * adapters. Holds the secrets; `sb` stays isomorphic.
 */
export function createServer<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  sb: BetterSupabase<M, D, F, E, C, P>,
  options: ServerOptions = {},
): BetterServer<M, F, E, C, P> {
  let loaded: BetterSupabaseEnv | undefined;
  const env = (): BetterSupabaseEnv => (loaded ??= options.env ?? loadEnv());
  let adminClient: SupabaseClient | undefined;
  let anonClient: SupabaseClient | undefined;

  const secretKey = (): string => {
    const key = env().secretKey;
    if (!key) {
      throw new TypeError("admin() needs SUPABASE_SECRET_KEY; it is not set");
    }
    return key;
  };
  const serviceClient = (): SupabaseClient => {
    adminClient ??= createClient(env().url, secretKey(), { auth: STATELESS });
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
    const global =
      Object.keys(headers).length > 0 ? { global: { headers } } : undefined;
    const shared = !global && url === env().url;
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

  const dbFor = (
    auth: AuthState,
    context: RequestContext = {},
  ): Db<M, F, E, SupabaseClient> =>
    sb.connect(supabaseFor(auth), { ...authContext(auth), ...context });

  const sqlFor = (
    claims: SqlClaims,
    context: RequestContext,
    stats?: StatsRecorder,
  ): Db<M, F, E, undefined> => {
    if (!options.postgres) {
      throw new TypeError(
        "Direct Postgres access needs createServer(sb, { postgres: createPostgres() })",
      );
    }
    return sb.connect(
      postgresExecutor(options.postgres.asUser(claims)),
      context,
      stats ? { stats } : {},
    );
  };

  /** Clients and repositories are built on first access: most scopes use one of them. */
  const contextFor = (
    resolution: AuthResolution<C, P>,
    headers: Readonly<Record<string, string>>,
    parent: StatsRecorder | undefined,
    until = 0,
  ): ServerContext<M, F, E, C, P> => {
    const { auth } = resolution;
    const context = authContext(auth);
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
        db = sb.connect(client(), context, {
          stats: recorder,
          ...(url && replica
            ? {
                executor: routedExecutor(
                  postgrestExecutor(client()),
                  postgrestExecutor(supabaseAt(url, auth, headers)),
                  replica,
                ),
              }
            : {}),
        });
        return db;
      },
      get replica() {
        replicaUrl();
        return replica;
      },
      get sql() {
        if (!options.postgres || !sqlClaims) return;
        sql ??= sqlFor(sqlClaims, context, recorder);
        return sql;
      },
      stats: () => recorder.snapshot(),
    };
  };

  const resolve = async (
    request: Request,
    resolveOptions: { readonly refresh?: boolean } = {},
  ): Promise<AuthResolution<C, P>> => {
    const claims = options.auth?.claims ?? sb.claimsSchema;
    const userMetadata = sb.userMetadataSchema;
    const resolved = await resolveAuth(request, {
      logger: sb.events.logger,
      ...options.auth,
      ...(claims ? { claims } : {}),
      ...(userMetadata ? { userMetadata } : {}),
      env: env(),
      ...(resolveOptions.refresh === undefined
        ? {}
        : { refresh: resolveOptions.refresh }),
      onRefresh: (event) => {
        options.auth?.onRefresh?.(event);
        sb.events.emit("refresh", event);
      },
    });
    // The claims schema's output is merged into every verified user's claims,
    // and the userMetadata schema's output is the profile.
    // SAFETY: the resolver ran the claims and userMetadata schemas, so resolved
    // has their output types.
    const resolution = resolved as AuthResolution<C, P>;
    if (sb.events.has("auth")) {
      const { auth } = resolution;
      sb.events.emit("auth", {
        source:
          auth.kind === "user"
            ? auth.source === "cookie"
              ? "cookie"
              : "bearer"
            : auth.kind === "service"
              ? "bearer"
              : "none",
        ok: auth.kind !== "invalid",
        ...(auth.kind === "user" ? { userId: auth.user.id } : {}),
      });
    }
    return resolution;
  };

  return {
    get env() {
      return env();
    },
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
      ),
    async context(request, contextOptions = {}) {
      const resolution = await resolve(request, {
        refresh: contextOptions.refresh ?? false,
      });
      return contextFor(
        resolution,
        options.headers?.(request) ?? {},
        contextOptions.stats,
        contextOptions.pinnedUntil ??
          pinnedUntil(request.headers.get("cookie")),
      );
    },
    admin: (context = {}) =>
      sb.connect(serviceClient(), {
        actor: { id: "service", kind: "service", role: "service_role" },
        claims: { role: "service_role" },
        ...context,
      }),
    deleteAccount: (userId, deleteOptions) =>
      deleteAccount(sb, serviceClient, userId, deleteOptions),
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
  };
}
