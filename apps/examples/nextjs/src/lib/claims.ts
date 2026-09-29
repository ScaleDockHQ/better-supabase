import { z } from 'zod';

const Role = z.enum(['admin', 'member']);
/** Stripe entitlement lookup keys the app sells. */
export const Entitlement = z.enum(['exports', 'sso', 'audit']);

/**
 * The claims the servers validate on every request (`sb.claims(Claims)`).
 * `user_role` comes from the custom access token hook
 * (supabase/migrations/*_rbac.sql), `org_id` from `app_metadata`. An unknown
 * role reads as none instead of rejecting the token.
 */
export const Claims = z.object({
  user_role: Role.optional().catch(undefined),
  // Loose, so the rest of `app_metadata` (provider, ...) is kept.
  app_metadata: z
    .looseObject({
      org_id: z.uuid().optional(),
      user_role: Role.optional().catch(undefined),
    })
    .optional(),
  // `better_supabase.membership_claims()` in the hook (entitlements kit module).
  memberships: z
    .array(
      z.object({
        tenant_id: z.uuid(),
        roles: z.array(z.string()).default([]),
        entitlements: z.array(Entitlement).default([]),
      }),
    )
    .optional()
    .catch(undefined),
});

export type Claims = z.infer<typeof Claims>;
export type Role = z.infer<typeof Role>;
export type Entitlement = z.infer<typeof Entitlement>;
