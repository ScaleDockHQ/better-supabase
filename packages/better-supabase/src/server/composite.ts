import type { Entry, SingleKeyEntry } from "@supabase/middleware";
import type { AuthMode, JWTClaims, UserClaims } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

import { defineComposite } from "@supabase/middleware";

import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { Db } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { ServerContextIn } from "./entries/context.ts";
import type { ServerCore } from "./entries/core.ts";
import type { GuardEntryConfig } from "./entries/guard.ts";
import type { SessionEntryConfig } from "./entries/session.ts";
import type { SqlIn } from "./entries/sql.ts";
import type { ReplicaState } from "./replicas.ts";
import type { GuardOptions } from "./respond.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "./server-types.ts";
import type { ActiveSupport } from "./support.ts";

import {
  withAuth,
  withAuthMode,
  withJwtClaims,
  withUserClaims,
} from "../auth/claims.ts";
import { withServerContext } from "./entries/context.ts";
import { serverCore } from "./entries/core.ts";
import { withDb } from "./entries/db.ts";
import { withGuard } from "./entries/guard.ts";
import { withReplica } from "./entries/replica.ts";
import { withSession } from "./entries/session.ts";
import { withSql } from "./entries/sql.ts";
import { withSupport } from "./entries/support.ts";
import { withTenant } from "./entries/tenant.ts";
import { createServer } from "./server.ts";

/** What `withBetterSupabase` takes besides the definition or server. */
export interface BetterSupabaseConfig
  extends SessionEntryConfig, GuardEntryConfig {}

/** The keys `withBetterSupabase` puts on `ctx`. */
export interface BetterSupabaseContributions<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  /**
   * The full request context: `auth`, `supabase`, `stats()`, `apply()` and the
   * rest.
   */
  bsb: ServerContext<M, F, E, C, P, B>;
  /** The verified token's payload, or `null`; the key `withSupabase` uses. */
  jwtClaims: (JWTClaims & C) | null;
  userClaims: UserClaims | null;
  authMode: AuthMode;
  /** Repositories over PostgREST as the caller. */
  db: Db<M, F, E, SupabaseClient, B>;
  /**
   * Repositories over direct Postgres as the caller, when Postgres is
   * configured or upstream.
   */
  sql: Db<M, F, E, undefined, B> | undefined;
  tenant: string | undefined;
  support: ActiveSupport | undefined;
  replica: ReplicaState | undefined;
}

/**
 * The entry `withBetterSupabase` returns, for `pipeline` and the framework
 * bridges.
 */
export type BetterSupabaseEntry<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> = Entry<BetterSupabaseContributions<M, F, E, C, P, B>>;

type Ctx<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
> = ServerContext<M, F, E, C, P, B>;

/** The single-key entries `withBetterSupabase` bundles, outermost first. */
export type BetterSupabaseParts<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
> = readonly [
  SingleKeyEntry<"session", Record<never, never>, AuthResolution<C, P>>,
  SingleKeyEntry<
    "tenant",
    { readonly session: AuthResolution<C, P> },
    string | undefined
  >,
  SingleKeyEntry<
    "support",
    { readonly session: AuthResolution<C, P> },
    ActiveSupport | undefined
  >,
  SingleKeyEntry<"bsb", ServerContextIn<C, P>, Ctx<M, F, E, C, P, B>>,
  SingleKeyEntry<
    "auth",
    { readonly bsb: { readonly auth: AuthState<C, P> } },
    AuthState<C, P>
  >,
  SingleKeyEntry<"guard", { readonly auth: AuthState<C, P> }, GuardOptions>,
  SingleKeyEntry<
    "jwtClaims",
    { readonly auth: AuthState<C, P> },
    (JWTClaims & C) | null
  >,
  SingleKeyEntry<
    "userClaims",
    { readonly auth: AuthState<C, P> },
    UserClaims | null
  >,
  SingleKeyEntry<"authMode", { readonly auth: AuthState<C, P> }, AuthMode>,
  SingleKeyEntry<
    "db",
    { readonly bsb: { readonly db: Db<M, F, E, SupabaseClient, B> } },
    Db<M, F, E, SupabaseClient, B>
  >,
  SingleKeyEntry<
    "sql",
    SqlIn<M, F, E, C, P, B>,
    Db<M, F, E, undefined, B> | undefined
  >,
  SingleKeyEntry<
    "replica",
    { readonly bsb: Ctx<M, F, E, C, P, B> },
    ReplicaState | undefined
  >,
];

/**
 * The single-key entries `withBetterSupabase` bundles, outermost first. The
 * framework factories run these directly, so their terminal sees `auth`.
 */
function betterSupabaseParts<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
>(
  core: ServerCore<M, F, E, C, P, B>,
  config: BetterSupabaseConfig = {},
): BetterSupabaseParts<M, F, E, C, P, B> {
  const {
    refresh,
    cookies,
    waitUntil,
    encode,
    cookieScopes,
    verifySession,
    ...guardConfig
  } = config;

  return [
    withSession(core, {
      ...(refresh === undefined ? {} : { refresh }),
      ...(cookies === undefined ? {} : { cookies }),
      ...(waitUntil === undefined ? {} : { waitUntil }),
      ...(encode === undefined ? {} : { encode }),
      ...(cookieScopes === undefined ? {} : { cookieScopes }),
      ...(verifySession === undefined ? {} : { verifySession }),
    }),
    withTenant(core),
    withSupport(core),
    withServerContext(core),
    withAuth<C, P>(),
    withGuard<C, P>(guardConfig),
    withJwtClaims<C, P>(),
    withUserClaims<C, P>(),
    withAuthMode<C, P>(),
    withDb<M, F, E, B>(),
    withSql<M, F, E, C, P, B>(),
    withReplica(core),
  ] as const;
}

function isDefinition<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
>(
  source: BetterSupabase<M, D, F, E, C, P, B> | BetterServer<M, F, E, C, P, B>,
): source is BetterSupabase<M, D, F, E, C, P, B> {
  return "connect" in source && typeof source.connect === "function";
}

/**
 * The whole better-supabase server as one `@supabase/middleware` entry: it
 * verifies the caller (bearer token or session cookie), refuses callers the
 * guard rejects with Problem Details, and contributes `ctx.db`, `ctx.sql`,
 * `ctx.bsb` and the `withSupabase` keys (`jwtClaims`, `userClaims`,
 * `authMode`), so `withPostgresClient` and `withOpenFeature` compose after it.
 * Refreshed cookies and `bsb-primary-until` go out on the response.
 *
 * ```ts
 * export default {
 *   fetch: pipeline(
 *     [withBetterSupabase(betterSupabase)],
 *     async (req, ctx) =>
 *       Response.json(await ctx.db.notes.list().orThrow()),
 *   ),
 * };
 * ```
 *
 * Pass a server from `createServer` to share its clients and JWKS cache with
 * the rest of the app; pass the definition to build one with `config`'s server
 * options.
 */
export function withBetterSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  config?: BetterSupabaseConfig & ServerOptions,
): BetterSupabaseEntry<M, F, E, C, P, B>;
export function withBetterSupabase<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  server: BetterServer<M, F, E, C, P, B>,
  config?: BetterSupabaseConfig,
): BetterSupabaseEntry<M, F, E, C, P, B>;
export function withBetterSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
>(
  source: BetterSupabase<M, D, F, E, C, P, B> | BetterServer<M, F, E, C, P, B>,
  config: BetterSupabaseConfig & ServerOptions = {},
): BetterSupabaseEntry<M, F, E, C, P, B> {
  const server = isDefinition(source) ? createServer(source, config) : source;
  const core = serverCore(server);

  const {
    refresh,
    cookies,
    waitUntil,
    encode,
    cookieScopes,
    verifySession,
    allow,
    aal,
    scopes,
    expose,
  } = config;

  const parts = betterSupabaseParts(core, {
    ...(refresh === undefined ? {} : { refresh }),
    ...(cookies === undefined ? {} : { cookies }),
    ...(waitUntil === undefined ? {} : { waitUntil }),
    ...(encode === undefined ? {} : { encode }),
    ...(cookieScopes === undefined ? {} : { cookieScopes }),
    ...(verifySession === undefined ? {} : { verifySession }),
    ...(allow === undefined ? {} : { allow }),
    ...(aal === undefined ? {} : { aal }),
    ...(scopes === undefined ? {} : { scopes }),
    ...(expose === undefined ? {} : { expose }),
  });

  return defineComposite({
    build: () => parts,
    internal: ["session", "auth", "guard"],
  })();
}
