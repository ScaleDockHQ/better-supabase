import 'server-only';
import { type AuthSession, sessionStale } from 'better-supabase/next';
import { cacheLife } from 'next/cache';

import type { Claims } from '@/lib/claims';

import { next } from '@/lib/supabase.server';

/**
 * The verified session, cached per browser session. The proxy refreshes the
 * token; this only verifies it locally against the JWKS, so it never calls
 * the Auth server. Call it inside a `<Suspense>` boundary.
 */
export async function getSession(): Promise<AuthSession<Claims>> {
  'use cache: private';
  const session = await next.session();
  // Five minutes joins the App Shell; never past the token's expiry.
  cacheLife({ stale: sessionStale(session) });
  return session;
}
