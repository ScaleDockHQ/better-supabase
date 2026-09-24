import type { AuthMode, JWTClaims, UserClaims } from '@supabase/server';
import type { PostgresApi } from '@supabase/server/middleware/postgres';
import type { SupabaseClient } from '@supabase/supabase-js';

import { defineMiddleware, type Middleware } from '@supabase/middleware';

import type { BetterSupabase } from '../core/define.ts';
import type { Actor, RequestContext } from '../core/plugin.ts';
import type { Db } from '../core/repository-types.ts';
import type { AnyFunctions, AnyModels } from '../schema/types.ts';

import { postgresExecutor } from '../postgres/executor.ts';

/** The `withSupabase` context keys `withBetterSupabase` reads. */
export interface SupabaseAuthContext {
  readonly jwtClaims: JWTClaims | null;
  readonly userClaims: UserClaims | null;
  readonly authMode: AuthMode;
}

/** Repository context from a `@supabase/server` context. */
export function contextFromSupabase(ctx: SupabaseAuthContext): RequestContext {
  switch (ctx.authMode) {
    case 'user': {
      if (!ctx.userClaims) break;
      const actor: Actor = {
        id: ctx.userClaims.id,
        kind: 'user',
        ...(ctx.userClaims.role !== undefined
          ? { role: ctx.userClaims.role }
          : {}),
        ...(ctx.userClaims.email !== undefined
          ? { email: ctx.userClaims.email }
          : {}),
      };
      return { actor, claims: ctx.jwtClaims ?? {} };
    }
    case 'secret':
      return {
        actor: { id: 'service', kind: 'service', role: 'service_role' },
        claims: { role: 'service_role' },
      };
    case 'publishable':
    case 'none':
      break;
    default: {
      const exhaustive: never = ctx.authMode;
      return exhaustive;
    }
  }
  return {
    actor: { id: 'anon', kind: 'anon', role: 'anon' },
    claims: { role: 'anon' },
  };
}

/**
 * `@supabase/middleware` entry contributing `ctx.db`: repositories bound to
 * `ctx.supabase` (the caller-scoped client from `withSupabase`).
 *
 * ```ts
 * pipeline([withSupabase({ auth: 'user' }), withBetterSupabase(sb)()], (req, ctx) => ...)
 * ```
 */
export function withBetterSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(
  sb: BetterSupabase<M, D, F, E>,
): Middleware<
  'db',
  void,
  SupabaseAuthContext & { readonly supabase: SupabaseClient },
  Db<M, F, E, SupabaseClient>
> {
  return defineMiddleware({
    key: 'db',
    run:
      (_config: void) =>
      (
        _req: Request,
        ctx: SupabaseAuthContext & { readonly supabase: SupabaseClient },
      ) =>
        Promise.resolve({
          db: sb.connect(ctx.supabase, contextFromSupabase(ctx)),
        }),
  });
}

/**
 * Entry contributing `ctx.sql`: repositories over `ctx.postgres` from
 * `withPostgresClient`, which runs each query as the caller with RLS.
 */
export function withBetterPostgres<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(
  sb: BetterSupabase<M, D, F, E>,
): Middleware<
  'sql',
  void,
  SupabaseAuthContext & { readonly postgres: PostgresApi },
  Db<M, F, E, undefined>
> {
  return defineMiddleware({
    key: 'sql',
    run:
      (_config: void) =>
      (
        _req: Request,
        ctx: SupabaseAuthContext & { readonly postgres: PostgresApi },
      ) =>
        Promise.resolve({
          sql: sb.connect(
            postgresExecutor(ctx.postgres),
            contextFromSupabase(ctx),
          ),
        }),
  });
}
