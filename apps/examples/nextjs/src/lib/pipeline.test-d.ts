import type { AuthSession } from 'better-supabase/react';

import { defineMiddleware, pipeline } from '@supabase/middleware';
import { withSupabase } from '@supabase/server';
import { withBetterSupabase } from 'better-supabase/server';

import type { Claims } from '@/lib/claims';

import { sb } from '@/lib/supabase';

// Compile-time only. `permdock` is not on npm yet, so these stand-ins copy
// the shapes `permdock/supabase/middleware` and `permdock/supabase` export:
// `withPermDock` needs `ctx.jwtClaims` upstream and contributes `ctx.permdock`,
// and `subjectFromSupabaseSession` reads `{ kind, claims }`.
type SupabaseJwtClaims = {
  readonly sub: string;
  readonly [claim: string]: unknown;
};
type SupabaseSessionLike = { readonly kind: string; readonly claims?: unknown };
type PermDockLike = { can(permission: string, resource?: unknown): boolean };

const withPermDock = defineMiddleware({
  key: 'permdock',
  run:
    (_config: void) =>
    (
      _req: Request,
      _ctx: { readonly jwtClaims: SupabaseJwtClaims | null },
    ): Promise<{ permdock: PermDockLike }> =>
      Promise.resolve({ permdock: { can: () => false } }),
});
declare function subjectFromSupabaseSession(
  session: SupabaseSessionLike,
): unknown;

export const handler = pipeline(
  [withSupabase({ auth: 'user' }), withBetterSupabase(sb)(), withPermDock()],
  async (_req, ctx) => {
    if (!ctx.permdock.can('customers.read')) {
      return new Response(null, { status: 403 });
    }
    const tenant: unknown = ctx.jwtClaims?.['tenant_id'];
    const count = await ctx.db.customers.count().orThrow();
    return Response.json({ count, tenant });
  },
);

declare const session: AuthSession<Claims>;
subjectFromSupabaseSession(session);
