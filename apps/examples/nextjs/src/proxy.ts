import type { NextRequest } from 'next/server';

import { next } from './lib/supabase.server';

export const proxy = (request: NextRequest) => next.proxy(request);

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|webp)$).*)',
  ],
};
