import { type ProxyOptions, toSession } from 'better-supabase/next';
import { type NextRequest, NextResponse } from 'next/server';

import { requiredPermission } from './features/navigation/nav-items';
import { can } from './features/user/user-permissions';
import { next } from './lib/supabase.server';

/**
 * Optimistic redirects from the (locally verified) token. Pages, actions and
 * RLS still check; this only saves rendering a page the user can't use.
 */
const protect: NonNullable<ProxyOptions['protect']> = (auth, request) => {
  const { pathname } = request.nextUrl;
  if (pathname === '/login' || pathname.startsWith('/api/')) return undefined;
  // Prefetches never refresh; let the page render its own signed-out state.
  if (auth.kind === 'anon' && auth.reason === 'expired') return undefined;
  const session = toSession(auth);
  if (session.kind !== 'user')
    return NextResponse.redirect(new URL('/login', request.url));
  const permission = requiredPermission(pathname);
  if (permission && !can(session, permission))
    return NextResponse.redirect(new URL('/', request.url));
  return undefined;
};

export const proxy = (request: NextRequest) =>
  next.proxy(request, {
    protect,
    after: (response, auth) => {
      // Shared caches must never store a signed-in response.
      if (auth.kind === 'user') response.headers.append('vary', 'cookie');
    },
    serverTiming: process.env.NODE_ENV !== 'production',
  });

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|webp)$).*)',
  ],
};
