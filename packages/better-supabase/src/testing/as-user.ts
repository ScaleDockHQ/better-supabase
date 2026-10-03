import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { BetterPostgres } from "../postgres/pool.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { ENV_VARIABLES } from "../env/index.ts";
import { postgresExecutor } from "../postgres/executor.ts";
import {
  type SigningJwk,
  signTestJwt,
  signTestJwtWithKey,
  type TestJwtClaims,
} from "./jwt.ts";
import { localSigningKey } from "./local-key.ts";

/** The local CLI stack's default JWT secret. */
export const LOCAL_JWT_SECRET =
  "super-secret-jwt-token-with-at-least-32-characters-long";

export interface LocalStack {
  /** Defaults to `$SUPABASE_URL`, then `http://127.0.0.1:54321`. */
  readonly url?: string;
  /** Defaults to `$SUPABASE_PUBLISHABLE_KEY`, then `$SUPABASE_ANON_KEY`. */
  readonly publishableKey?: string;
  /**
   * `ES256` (default) signs with the key `better-supabase keys` wrote, as
   * the hosted project's asymmetric keys do. `HS256` signs with the shared
   * JWT secret and only works against a local stack.
   */
  readonly alg?: "ES256" | "HS256";
  /** The private ES256 key. Defaults to the first key in `signingKeysPath`. */
  readonly signingKey?: SigningJwk;
  /** Defaults to `$SUPABASE_SIGNING_KEYS_PATH`, then `signing_keys_path` in `supabase/config.toml`. */
  readonly signingKeysPath?: string;
  /** For `alg: 'HS256'`. Defaults to `$SUPABASE_JWT_SECRET`, then the CLI default. */
  readonly jwtSecret?: string;
  /** Service-role key for `expectTenantIsolation`; defaults to `$SUPABASE_SECRET_KEY`. */
  readonly secretKey?: string;
  /** Enables `sql`: the same user over direct Postgres. */
  readonly postgres?: BetterPostgres;
}

export interface TestUser<M extends AnyModels, F extends AnyFunctions, E> {
  readonly token: string;
  readonly claims: TestJwtClaims;
  /** supabase-js signed in as the user (storage, realtime, functions). */
  readonly supabase: SupabaseClient;
  /** Repositories over PostgREST as the user; RLS applies. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** Repositories over direct Postgres as the user, when `postgres` is given. */
  readonly sql: Db<M, F, E, unknown> | undefined;
}

function env(...names: readonly string[]): string | undefined {
  if (typeof process === "undefined") return undefined;
  for (const name of names) {
    const value = process.env[name];
    if (value) return value;
  }
  return undefined;
}

const LOCAL_HOSTS = new Set([
  "localhost",
  "127.0.0.1",
  "[::1]",
  "host.docker.internal",
]);

async function signFor(
  stack: LocalStack,
  url: string,
  claims: TestJwtClaims,
): Promise<string> {
  const alg = stack.alg ?? "ES256";
  switch (alg) {
    case "ES256":
      return signTestJwtWithKey(
        stack.signingKey ?? (await localSigningKey(stack.signingKeysPath)),
        claims,
      );
    case "HS256": {
      if (!LOCAL_HOSTS.has(new URL(url).hostname)) {
        throw new TypeError(
          `asUser signs HS256 tokens only for a local stack, not ${url}. Use the ES256 key from \`better-supabase keys\`.`,
        );
      }
      const secret =
        stack.jwtSecret ?? env("SUPABASE_JWT_SECRET") ?? LOCAL_JWT_SECRET;
      return signTestJwt(secret, claims);
    }
    default: {
      const unknown: never = alg;
      throw new TypeError(`asUser: unknown alg "${String(unknown)}"`);
    }
  }
}

/**
 * A test user against the local stack: a signed token and repositories that
 * run as that user, for live RLS tests. The token is ES256-signed with the
 * key from `better-supabase keys`; pass `{ alg: 'HS256' }` for a stack that
 * still uses the shared JWT secret.
 *
 * ```ts
 * const alice = await asUser(betterSupabase, { sub: aliceId, tenant_id: acme });
 * expect(await alice.db.customers.count().orThrow()).toBe(3);
 * ```
 */
export async function asUser<M extends AnyModels, D, F extends AnyFunctions, E>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  claims: TestJwtClaims,
  stack: LocalStack = {},
): Promise<TestUser<M, F, E>> {
  const url =
    stack.url ?? env(...ENV_VARIABLES.url) ?? "http://127.0.0.1:54321";
  const publishableKey =
    stack.publishableKey ??
    env(...ENV_VARIABLES.publishableKey, "SUPABASE_ANON_KEY");
  if (!publishableKey) {
    throw new TypeError(
      "asUser needs publishableKey or $SUPABASE_PUBLISHABLE_KEY. Run `better-supabase env` to write it to .env.local.",
    );
  }
  const token = await signFor(stack, url, claims);
  const full: TestJwtClaims = { role: "authenticated", ...claims };
  const context: RequestContext = {
    actor: {
      id: claims.sub,
      kind: "user",
      role: full.role ?? "authenticated",
      ...(typeof claims.email === "string" ? { email: claims.email } : {}),
    },
    claims: full,
  };
  const supabase = createClient(url, publishableKey, {
    accessToken: () => Promise.resolve(token),
  });
  return {
    token,
    claims: full,
    supabase,
    db: betterSupabase.connect(supabase, context),
    sql: stack.postgres
      ? betterSupabase.connect(
          postgresExecutor(stack.postgres.asUser(full)),
          context,
        )
      : undefined,
  };
}
