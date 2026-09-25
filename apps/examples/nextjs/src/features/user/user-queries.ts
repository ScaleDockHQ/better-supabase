import 'server-only';
import type { AuthSession } from 'better-supabase/next';

import { cacheLife } from 'next/cache';

import { next } from '@/lib/supabase.server';

/** Five minutes: the minimum `stale` for a private read to join the App Shell. */
const APP_SHELL_STALE = 300;
/** The minimum `stale` for per-link prefetching. */
const PREFETCH_STALE = 30;

/**
 * The verified session, cached per browser session. The proxy refreshes the
 * token; this only verifies it locally against the JWKS, so it never calls
 * the Auth server. Call it inside a `<Suspense>` boundary.
 */
export async function getSession(): Promise<AuthSession> {
  'use cache: private';
  const session = await next.session();
  cacheLife({ stale: staleFor(session) });
  return session;
}

/** Never keep a signed-in view on the client past the token's expiry. */
function staleFor(session: AuthSession): number {
  if (session.kind !== 'user' || session.expiresAt === null)
    return APP_SHELL_STALE;
  const remaining = session.expiresAt - Math.floor(Date.now() / 1000);
  return Math.min(APP_SHELL_STALE, Math.max(PREFETCH_STALE, remaining));
}
