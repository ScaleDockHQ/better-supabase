import { z } from 'zod';

const Role = z.enum(['admin', 'member']);
/** Stripe entitlement lookup keys the app sells. */
export const Entitlement = z.enum(['exports', 'sso', 'audit']);

const isEntitlement = (key: string): key is Entitlement =>
  Entitlement.safeParse(key).success;

/**
 * The claims the servers validate on every request (`sb.claims(Claims)`),
 * in PermDock's claim contract. `user_role` comes from the custom access
 * token hook (supabase/migrations/*_rbac.sql), `tenant_id` from the hook or
 * `app_metadata`. An unknown role reads as none instead of rejecting the
 * token.
 *
 * Every object is loose, so claims this schema doesn't name (`authz_ver`,
 * `memberships_truncated`, `attrs`) reach PermDock unchanged.
 */
export const Claims = z.looseObject({
  user_role: Role.optional().catch(undefined),
  tenant_id: z.uuid().optional(),
  app_metadata: z
    .looseObject({
      tenant_id: z.uuid().optional(),
      user_role: Role.optional().catch(undefined),
    })
    .optional(),
  // `better_supabase.membership_claims()` or PermDock's hook.
  memberships: z
    .array(
      z.looseObject({
        scope: z.string(),
        id: z.string(),
        roles: z.array(z.string()).default([]),
      }),
    )
    .optional()
    .catch(undefined),
  // `better_supabase.feature_claims()` (entitlements kit module). Keys the
  // app doesn't sell yet are dropped instead of rejecting the token.
  features: z
    .record(
      z.string(),
      z.array(z.string()).transform((keys) => keys.filter(isEntitlement)),
    )
    .optional()
    .catch(undefined),
});

/** Editable by the user (`auth.updateUser()`): display only, never access. */
export const Profile = z.looseObject({
  display_name: z.string().max(80).optional(),
  avatar_url: z.url().optional(),
});

export type Claims = z.infer<typeof Claims>;
export type Profile = z.infer<typeof Profile>;
export type Role = z.infer<typeof Role>;
export type Entitlement = z.infer<typeof Entitlement>;
