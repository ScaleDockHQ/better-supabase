import type { PermissionSet } from "better-supabase/blocks/permissions";
import type { AuthSession } from "better-supabase/react";

import { can as holds } from "better-supabase/blocks/permissions";
import { tenantOf } from "better-supabase/react";
import * as v from "valibot";

import type { Claims } from "@/lib/claims";
import type { PermissionKey } from "@/lib/supabase/blocks.generated";

import { MEMBERSHIP_SCOPE, Role } from "@/lib/claims";

export type { PermissionSet } from "better-supabase/blocks/permissions";

/**
 * Keys only the app's own SQL checks (`public.subscriptions`). The config has
 * no place for them, so `gen` leaves them out of `PermissionKey`; the data
 * migration adds them to the catalog.
 */
type AppPermission = "billing.read" | "billing.manage";

/** A key of the permissions catalog (`better_supabase.permissions`). */
export type Permission = PermissionKey | AppPermission;

/**
 * Whether the caller's set holds `permission`. The set is `my_permissions` in
 * the active organization: the role's keys with the organization's overrides
 * applied (`getPermissions` on the server, `usePermissions` on the client). UI
 * only: RLS and the SQL functions check the key again.
 */
export function can(
  set: PermissionSet | null | undefined,
  permission: Permission,
): boolean {
  return holds(set, permission);
}

/**
 * The role key of the membership in the active organization, from the
 * `memberships` claim. Never `user_metadata`: users can edit that.
 */
export function roleOf(session: AuthSession<Claims>): Role | undefined {
  const tenant = tenantOf(session);

  if (session.kind !== "user" || tenant === undefined) {
    return undefined;
  }

  const membership = session.claims.memberships?.find(
    (entry) => entry.scope === MEMBERSHIP_SCOPE && entry.id === tenant,
  );

  return membership?.roles.find((role): role is Role => v.is(Role, role));
}
