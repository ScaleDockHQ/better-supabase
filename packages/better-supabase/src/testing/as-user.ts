import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import type { BetterSupabase } from '../core/define.ts';
import type { RequestContext } from '../core/plugin.ts';
import type { Db } from '../core/repository-types.ts';
import type { Postgres } from '../postgres/pool.ts';
import type { AnyFunctions, AnyModels } from '../schema/types.ts';

import { ENV_VARIABLES } from '../env/index.ts';
import { postgresExecutor } from '../postgres/executor.ts';
import { signTestJwt, type TestJwtClaims } from './jwt.ts';

/** The local CLI stack's default JWT secret. */
export const LOCAL_JWT_SECRET =
  'super-secret-jwt-token-with-at-least-32-characters-long';

export interface LocalStack {
  /** Defaults to `$SUPABASE_URL`, then `http://127.0.0.1:54321`. */
  readonly url?: string;
  /** Defaults to `$SUPABASE_PUBLISHABLE_KEY`, then `$SUPABASE_ANON_KEY`. */
  readonly publishableKey?: string;
  /** Defaults to `$SUPABASE_JWT_SECRET`, then the CLI default. */
  readonly jwtSecret?: string;
  /** Service-role key for `expectTenantIsolation`; defaults to `$SUPABASE_SECRET_KEY`. */
  readonly secretKey?: string;
  /** Enables `sql`: the same user over direct Postgres. */
  readonly postgres?: Postgres;
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
  if (typeof process === 'undefined') return undefined;
  for (const name of names) {
    const value = process.env[name];
    if (value) return value;
  }
  return undefined;
}

/**
 * A test user against the local stack: a signed token and repositories that
 * run as that user, for live RLS tests.
 *
 * ```ts
 * const alice = await asUser(sb, { sub: aliceId, org_id: acme });
 * expect(await alice.db.customers.count().orThrow()).toBe(3);
 * ```
 */
export async function asUser<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  claims: TestJwtClaims,
  stack: LocalStack = {},
): Promise<TestUser<M, F, E>> {
  const url =
    stack.url ?? env(...ENV_VARIABLES.url) ?? 'http://127.0.0.1:54321';
  const publishableKey =
    stack.publishableKey ??
    env(...ENV_VARIABLES.publishableKey, 'SUPABASE_ANON_KEY');
  if (!publishableKey) {
    throw new TypeError(
      'asUser needs publishableKey or $SUPABASE_PUBLISHABLE_KEY. Run `better-supabase env` to write it to .env.local.',
    );
  }
  const secret =
    stack.jwtSecret ?? env('SUPABASE_JWT_SECRET') ?? LOCAL_JWT_SECRET;
  const token = await signTestJwt(secret, claims);
  const full: TestJwtClaims = { role: 'authenticated', ...claims };
  const context: RequestContext = {
    actor: {
      id: claims.sub,
      kind: 'user',
      role: full.role ?? 'authenticated',
      ...(typeof claims.email === 'string' ? { email: claims.email } : {}),
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
    db: sb.connect(supabase, context) as Db<M, F, E, SupabaseClient>,
    sql: stack.postgres
      ? (sb.connect(
          postgresExecutor(stack.postgres.asUser(full)),
          context,
        ) as Db<M, F, E, unknown>)
      : undefined,
  };
}
