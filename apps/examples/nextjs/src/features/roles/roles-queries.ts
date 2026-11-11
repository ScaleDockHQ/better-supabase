import "server-only";
import type { CatalogRole } from "better-supabase/blocks/permissions";

import { can as holds } from "better-supabase/blocks/permissions";
import { tenantOf } from "better-supabase/next";
import { cacheLife, cacheTag } from "next/cache";
import * as v from "valibot";

import type { PermissionSet } from "@/features/user/user-permissions";

import { organizationSnapshotTag } from "@/features/user/user-cache";
import { Role } from "@/lib/claims";
import { bsbCore } from "@/lib/supabase/server-core";

export type { CatalogRole } from "better-supabase/blocks/permissions";

/**
 * The organization's catalog roles through the permissions block's
 * `list_roles`: default and effective keys, overrides and member counts. `null`
 * without an organization. Refused without `members.read`.
 */
export async function getRoles(): Promise<readonly CatalogRole[] | null> {
  "use cache: private";
  const { db, session } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (tenant === undefined) {
    return null;
  }

  // Every role write calls updateTag(organizationSnapshotTag), so the entry
  // never needs to expire on a timer.
  cacheLife("max");
  cacheTag(organizationSnapshotTag(tenant));

  return db.permissions.roles().orThrow();
}

/**
 * The roles the caller may give: each one whose keys in this organization the
 * caller holds, the rule `better_supabase.can_assign` applies. UI only: the SQL
 * functions check it again.
 */
export function assignableRoles(
  roles: readonly CatalogRole[],
  held: PermissionSet | null,
): readonly Role[] {
  return roles.flatMap((role) =>
    v.is(Role, role.key) &&
    role.permissions.every((permission) => holds(held, permission))
      ? [role.key]
      : [],
  );
}
