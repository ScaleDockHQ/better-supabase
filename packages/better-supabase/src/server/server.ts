import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import type { BetterSupabase } from '../core/define.ts';
import type { RequestContext } from '../core/plugin.ts';
import type { Db } from '../core/repository-types.ts';
import type { Postgres, SqlClaims } from '../postgres/pool.ts';
import type { AnyFunctions, AnyModels } from '../schema/types.ts';

import {
  type AuthResolution,
  type AuthState,
  authContext,
  resolveAuth,
  type ResolveAuthOptions,
} from '../auth/resolve.ts';
import { type BetterSupabaseEnv, loadEnv } from '../env/index.ts';
import { postgresExecutor } from '../postgres/executor.ts';

export interface ServerOptions {
  /** Defaults to `loadEnv()`. */
  readonly env?: BetterSupabaseEnv;
  /** Enables `ctx.sql` and `actingAs()`. */
  readonly postgres?: Postgres;
  readonly auth?: Omit<ResolveAuthOptions, 'env'>;
  /**
   * Extra headers on the caller's PostgREST requests, readable in Postgres as
   * `current_setting('request.headers')` (channel, request id, client IP for audit).
   */
  readonly headers?: (request: Request) => Readonly<Record<string, string>>;
}

export interface ServerContext<M extends AnyModels, F extends AnyFunctions, E> {
  readonly auth: AuthState;
  readonly resolution: AuthResolution;
  /** supabase-js client scoped to the caller (RLS applies). */
  readonly supabase: SupabaseClient;
  /** Repositories over PostgREST as the caller. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** Repositories over direct Postgres as the caller, when `postgres` is configured. */
  readonly sql: Db<M, F, E, undefined> | undefined;
}

export interface BetterServer<M extends AnyModels, F extends AnyFunctions, E> {
  readonly env: BetterSupabaseEnv;
  resolve(
    request: Request,
    options?: { readonly refresh?: boolean },
  ): Promise<AuthResolution>;
  /**
   * Resolves auth and binds repositories to the caller. Refreshes an expired
   * cookie session only with `refresh: true`; send `ctx.resolution.apply(response)`.
   */
  context(
    request: Request,
    options?: { readonly refresh?: boolean },
  ): Promise<ServerContext<M, F, E>>;
  /** A stateless supabase-js client for an auth state, optionally with extra request headers. */
  supabaseFor(
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ): SupabaseClient;
  /** Repositories for an auth state (e.g. one resolved by the proxy). */
  dbFor(auth: AuthState, context?: RequestContext): Db<M, F, E, SupabaseClient>;
  /** Service-role repositories. Bypasses RLS; the actor is `service`. */
  admin(context?: RequestContext): Db<M, F, E, SupabaseClient>;
  /** Repositories running as a user, with RLS, over direct Postgres. */
  actingAs(
    userId: string,
    claims?: Omit<SqlClaims, 'sub'>,
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
  return Object.defineProperties(
    {},
    {
      ...Object.getOwnPropertyDescriptors(server),
      ...Object.getOwnPropertyDescriptors(extra),
    },
  ) as R;
}

/**
 * Server-side entry point for APIs, jobs, MCP servers and framework
 * adapters. Holds the secrets; `sb` stays isomorphic.
 */
export function createServer<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  options: ServerOptions = {},
): BetterServer<M, F, E> {
  let loaded: BetterSupabaseEnv | undefined;
  const env = (): BetterSupabaseEnv => (loaded ??= options.env ?? loadEnv());
  let adminClient: SupabaseClient | undefined;
  let anonClient: SupabaseClient | undefined;

  const secretKey = (): string => {
    const key = env().secretKey;
    if (!key) {
      throw new TypeError('admin() needs SUPABASE_SECRET_KEY; it is not set');
    }
    return key;
  };
  const serviceClient = (): SupabaseClient => {
    adminClient ??= createClient(env().url, secretKey(), { auth: STATELESS });
    return adminClient;
  };

  const supabaseFor = (
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => {
    const global =
      Object.keys(headers).length > 0 ? { global: { headers } } : undefined;
    switch (auth.kind) {
      case 'user':
        return createClient(env().url, env().publishableKey, {
          accessToken: () => Promise.resolve(auth.token),
          ...global,
        });
      case 'service':
        return global
          ? createClient(env().url, secretKey(), { auth: STATELESS, ...global })
          : serviceClient();
      case 'anon':
      case 'invalid':
        if (global) {
          return createClient(env().url, env().publishableKey, {
            auth: STATELESS,
            ...global,
          });
        }
        anonClient ??= createClient(env().url, env().publishableKey, {
          auth: STATELESS,
        });
        return anonClient;
      default: {
        const exhaustive: never = auth;
        return exhaustive;
      }
    }
  };

  const dbFor = (
    auth: AuthState,
    context: RequestContext = {},
  ): Db<M, F, E, SupabaseClient> =>
    sb.connect(supabaseFor(auth), { ...authContext(auth), ...context });

  const sqlFor = (
    claims: SqlClaims,
    context: RequestContext,
  ): Db<M, F, E, undefined> => {
    if (!options.postgres) {
      throw new TypeError(
        'Direct Postgres access needs createServer(sb, { postgres: createPostgres() })',
      );
    }
    return sb.connect(
      postgresExecutor(options.postgres.asUser(claims)),
      context,
    );
  };

  const resolve = async (
    request: Request,
    resolveOptions: { readonly refresh?: boolean } = {},
  ): Promise<AuthResolution> => {
    const resolution = await resolveAuth(request, {
      ...options.auth,
      env: env(),
      ...(resolveOptions.refresh !== undefined
        ? { refresh: resolveOptions.refresh }
        : {}),
      onRefresh: (event) => {
        options.auth?.onRefresh?.(event);
        sb.events.emit('refresh', event);
      },
    });
    if (sb.events.has('auth')) {
      const { auth } = resolution;
      sb.events.emit('auth', {
        source:
          auth.kind === 'user'
            ? auth.source === 'cookie'
              ? 'cookie'
              : 'bearer'
            : auth.kind === 'service'
              ? 'bearer'
              : 'none',
        ok: auth.kind !== 'invalid',
        ...(auth.kind === 'user' ? { userId: auth.user.id } : {}),
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
    async context(request, contextOptions = {}) {
      const resolution = await resolve(request, {
        refresh: contextOptions.refresh ?? false,
      });
      const { auth } = resolution;
      const context = authContext(auth);
      const supabase = supabaseFor(auth, options.headers?.(request));
      const sqlClaims: SqlClaims | undefined =
        auth.kind === 'user'
          ? auth.claims
          : auth.kind === 'anon'
            ? { role: 'anon' }
            : undefined;
      return {
        auth,
        resolution,
        supabase,
        db: sb.connect(supabase, context),
        sql:
          options.postgres && sqlClaims
            ? sqlFor(sqlClaims, context)
            : undefined,
      };
    },
    admin: (context = {}) =>
      sb.connect(serviceClient(), {
        actor: { id: 'service', kind: 'service', role: 'service_role' },
        claims: { role: 'service_role' },
        ...context,
      }),
    actingAs: (userId, claims = {}) => {
      const full: SqlClaims = { role: 'authenticated', ...claims, sub: userId };
      return sqlFor(full, {
        actor: { id: userId, kind: 'user', role: full.role ?? 'authenticated' },
        claims: full,
      });
    },
  };
}
