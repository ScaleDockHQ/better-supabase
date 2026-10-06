import type { AuthMode, JWTClaims, UserClaims } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

import {
  defineComposite,
  type Entry,
  type SingleKeyEntry,
} from "@supabase/middleware";

import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { Db } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { ServerContextIn } from "./entries/context.ts";
import type { SqlIn } from "./entries/sql.ts";
import type { ReplicaState } from "./replicas.ts";
import type { GuardOptions } from "./respond.ts";
import type { BetterServer, ServerContext, ServerOptions } from "./server.ts";
import type { ActiveSupport } from "./support.ts";

import {
  withAuth,
  withAuthMode,
  withJwtClaims,
  withUserClaims,
} from "./entries/claims.ts";
import { withServerContext } from "./entries/context.ts";
import { type ServerCore, serverCore } from "./entries/core.ts";
import { withDb } from "./entries/db.ts";
import { type GuardEntryConfig, withGuard } from "./entries/guard.ts";
import { withReplica } from "./entries/replica.ts";
import { type SessionEntryConfig, withSession } from "./entries/session.ts";
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
> {
  /** The full request context: `auth`, `supabase`, `stats()`, `apply()` and the rest. */
  bs: ServerContext<M, F, E, C, P>;
  /** The verified token's payload, or `null`; the key `withSupabase` uses. */
  jwtClaims: (JWTClaims & C) | null;
  userClaims: UserClaims | null;
  authMode: AuthMode;
  /** Repositories over PostgREST as the caller. */
  db: Db<M, F, E, SupabaseClient>;
  /** Repositories over direct Postgres as the caller, when Postgres is configured or upstream. */
  sql: Db<M, F, E, undefined> | undefined;
  tenant: string | undefined;
  support: ActiveSupport | undefined;
  replica: ReplicaState | undefined;
}

/** The entry `withBetterSupabase` returns, for `pipeline` and the framework bridges. */
export type BetterSupabaseEntry<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = Entry<BetterSupabaseContributions<M, F, E, C, P>>;

type Ctx<M extends AnyModels, F extends AnyFunctions, E, C, P> = ServerContext<
  M,
  F,
  E,
  C,
  P
>;

/** The single-key entries `withBetterSupabase` bundles, outermost first. */
export type BetterSupabaseParts<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
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
  SingleKeyEntry<"bs", ServerContextIn<C, P>, Ctx<M, F, E, C, P>>,
  SingleKeyEntry<
    "auth",
    { readonly bs: { readonly auth: AuthState<C, P> } },
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
    { readonly bs: { readonly db: Db<M, F, E, SupabaseClient> } },
    Db<M, F, E, SupabaseClient>
  >,
  SingleKeyEntry<
    "sql",
    SqlIn<M, F, E, C, P>,
    Db<M, F, E, undefined> | undefined
  >,
  SingleKeyEntry<
    "replica",
    { readonly bs: Ctx<M, F, E, C, P> },
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
>(
  core: ServerCore<M, F, E, C, P>,
  config: BetterSupabaseConfig = {},
): BetterSupabaseParts<M, F, E, C, P> {
  const { refresh, cookies, waitUntil, encode, cookieScopes, ...guardConfig } =
    config;
  return [
    withSession(core, {
      ...(refresh === undefined ? {} : { refresh }),
      ...(cookies === undefined ? {} : { cookies }),
      ...(waitUntil === undefined ? {} : { waitUntil }),
      ...(encode === undefined ? {} : { encode }),
      ...(cookieScopes === undefined ? {} : { cookieScopes }),
    }),
    withTenant(core),
    withSupport(core),
    withServerContext(core),
    withAuth<C, P>(),
    withGuard<C, P>(guardConfig),
    withJwtClaims<C, P>(),
    withUserClaims<C, P>(),
    withAuthMode<C, P>(),
    withDb<M, F, E>(),
    withSql<M, F, E, C, P>(),
    withReplica(core),
  ] as const;
}

function isDefinition<M extends AnyModels, D, F extends AnyFunctions, E, C, P>(
  source: BetterSupabase<M, D, F, E, C, P> | BetterServer<M, F, E, C, P>,
): source is BetterSupabase<M, D, F, E, C, P> {
  return "connect" in source && typeof source.connect === "function";
}

/**
 * The whole better-supabase server as one `@supabase/middleware` entry: it
 * verifies the caller (bearer token or session cookie), refuses callers the
 * guard rejects with Problem Details, and contributes `ctx.db`, `ctx.sql`,
 * `ctx.bs` and the `withSupabase` keys (`jwtClaims`, `userClaims`,
 * `authMode`), so `withPostgresClient` and `withOpenFeature` compose after
 * it. Refreshed cookies and `bs-primary-until` go out on the response.
 *
 * ```ts
 * export default {
 *   fetch: pipeline([withBetterSupabase(betterSupabase)], async (req, ctx) =>
 *     Response.json(await ctx.db.notes.findMany().orThrow())),
 * }
 * ```
 *
 * Pass a server from `createServer` to share its clients and JWKS cache
 * with the rest of the app; pass the definition to build one with
 * `config`'s server options.
 */
export function withBetterSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  config?: BetterSupabaseConfig & ServerOptions,
): BetterSupabaseEntry<M, F, E, C, P>;
export function withBetterSupabase<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  server: BetterServer<M, F, E, C, P>,
  config?: BetterSupabaseConfig,
): BetterSupabaseEntry<M, F, E, C, P>;
export function withBetterSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  source: BetterSupabase<M, D, F, E, C, P> | BetterServer<M, F, E, C, P>,
  config: BetterSupabaseConfig & ServerOptions = {},
): BetterSupabaseEntry<M, F, E, C, P> {
  const server = isDefinition(source) ? createServer(source, config) : source;
  const core = serverCore(server);
  const {
    refresh,
    cookies,
    waitUntil,
    encode,
    cookieScopes,
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
