import type { AuthSession } from "better-supabase/react";

import { defineMiddleware, pipeline } from "@supabase/middleware";
import { withSupabase } from "@supabase/server";
import { withBetterDb } from "better-supabase/server";

import type { Claims } from "@/lib/claims";

import { betterSupabase } from "@/lib/supabase";

// Compile-time only. A third-party authorization middleware that reads
// `ctx.jwtClaims` and contributes `ctx.authorization` composes after
// `withBetterDb`, and a subject builder takes an `AuthSession` as it is.
/* oxlint-disable anti-slop/no-unsafe-dictionary-type, anti-slop/no-unknown-parameters, anti-slop/no-unknown-returns -- the stand-ins type a library this example doesn't install */
type SupabaseJwtClaims = {
  readonly sub: string;
  readonly [claim: string]: unknown;
};
type SessionLike = { readonly kind: string; readonly claims?: unknown };
type Authorization = { can(permission: string, resource?: unknown): boolean };

const withAuthorization = defineMiddleware({
  key: "authorization",
  run:
    (_config: void) =>
    (
      _req: Request,
      _ctx: { readonly jwtClaims: SupabaseJwtClaims | null },
    ): Promise<{ authorization: Authorization }> =>
      Promise.resolve({ authorization: { can: () => false } }),
});
declare function subjectFromSession(session: SessionLike): unknown;
/* oxlint-enable anti-slop/no-unsafe-dictionary-type, anti-slop/no-unknown-parameters, anti-slop/no-unknown-returns */

export const handler = pipeline(
  [
    withSupabase({ auth: "user" }),
    withBetterDb(betterSupabase)(),
    withAuthorization(),
  ],
  async (_req, ctx) => {
    if (!ctx.authorization.can("customers.read")) {
      return new Response(null, { status: 403 });
    }
    const tenant: unknown = ctx.jwtClaims?.["tenant_id"];
    const count = await ctx.db.customers.count().orThrow();
    return Response.json({ count, tenant });
  },
);

declare const session: AuthSession<Claims>;
subjectFromSession(session);
