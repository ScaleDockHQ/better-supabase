import * as v from "valibot";

const Role = v.picklist(["admin", "member"]);
/** Stripe entitlement lookup keys the app sells. */
export const Entitlement = v.picklist(["exports", "sso", "audit"]);

const isEntitlement = (key: string): key is Entitlement =>
  v.is(Entitlement, key);

/**
 * The scope of the tenant entries in `memberships`: `claims.scope` in
 * better-supabase.config.ts. PermDock's hook writes its declared scope
 * names, so with PermDock this is the manifest's root scope.
 */
export const MEMBERSHIP_SCOPE = "tenant";

/**
 * A role name or a list of them (PermDock's contract allows both, and `null`
 * for none). Unknown names are dropped instead of rejecting the token.
 */
const Roles = v.fallback(
  v.optional(
    v.pipe(
      v.nullable(
        v.union([
          v.pipe(
            v.string(),
            v.transform((role) => [role]),
          ),
          v.array(v.string()),
        ]),
      ),
      v.transform((roles) =>
        (roles ?? []).filter((role): role is Role => v.is(Role, role)),
      ),
    ),
  ),
  undefined,
);

const Membership = v.looseObject({
  scope: v.string(),
  id: v.string(),
  roles: v.optional(v.array(v.string()), []),
});

/**
 * Each entry is parsed on its own: PermDock's `tenant`, `team` and `on`
 * forms (no `scope` and `id`) are skipped instead of discarding the list.
 */
const Memberships = v.fallback(
  v.optional(
    v.pipe(
      v.array(v.unknown()),
      v.transform((entries) =>
        entries.flatMap((entry) => {
          const parsed = v.safeParse(Membership, entry);
          return parsed.success ? [parsed.output] : [];
        }),
      ),
    ),
  ),
  undefined,
);

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
  user_role: Roles,
  tenant_id: v.optional(v.pipe(v.string(), v.uuid())),
  app_metadata: v.optional(
    v.looseObject({
      tenant_id: v.optional(v.pipe(v.string(), v.uuid())),
      user_role: Roles,
    }),
  ),
  // `better_supabase.membership_claims()` or PermDock's hook.
  memberships: Memberships,
  // `better_supabase.feature_claims()` (entitlements block module). Keys the
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
