import * as v from "valibot";

const Role = v.picklist(["admin", "member"]);
/** Stripe entitlement lookup keys the app sells. */
export const Entitlement = v.picklist(["exports", "sso", "audit"]);

const isEntitlement = (key: string): key is Entitlement =>
  v.is(Entitlement, key);

/**
 * The claims the servers validate on every request (`betterSupabase.claims(Claims)`),
 * in PermDock's claim contract. `user_role` comes from the custom access
 * token hook (supabase/schemas/040_rbac.sql), `tenant_id` from the hook or
 * `app_metadata`. An unknown role reads as none instead of rejecting the
 * token.
 *
 * Every object is loose, so claims this schema doesn't name (`authz_ver`,
 * `memberships_truncated`, `attrs`) reach PermDock unchanged.
 */
export const Claims = v.looseObject({
  user_role: v.fallback(v.optional(Role), undefined),
  tenant_id: v.optional(v.pipe(v.string(), v.uuid())),
  app_metadata: v.optional(
    v.looseObject({
      tenant_id: v.optional(v.pipe(v.string(), v.uuid())),
      user_role: v.fallback(v.optional(Role), undefined),
    }),
  ),
  // `better_supabase.membership_claims()` or PermDock's hook.
  memberships: v.fallback(
    v.optional(
      v.array(
        v.looseObject({
          scope: v.string(),
          id: v.string(),
          roles: v.optional(v.array(v.string()), []),
        }),
      ),
    ),
    undefined,
  ),
  // `better_supabase.feature_claims()` (entitlements kit module). Keys the
  // app doesn't sell yet are dropped instead of rejecting the token.
  features: v.fallback(
    v.optional(
      v.record(
        v.string(),
        v.pipe(
          v.array(v.string()),
          v.transform((keys) => keys.filter(isEntitlement)),
        ),
      ),
    ),
    undefined,
  ),
});

/** Editable by the user (`auth.updateUser()`): display only, never access. */
export const Profile = v.looseObject({
  display_name: v.optional(v.pipe(v.string(), v.maxLength(80))),
  avatar_url: v.optional(v.pipe(v.string(), v.url())),
});

export type Claims = v.InferOutput<typeof Claims>;
export type Profile = v.InferOutput<typeof Profile>;
export type Role = v.InferOutput<typeof Role>;
export type Entitlement = v.InferOutput<typeof Entitlement>;
