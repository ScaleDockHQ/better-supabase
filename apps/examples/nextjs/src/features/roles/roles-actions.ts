"use server";

import { ok } from "better-supabase";
import { updateTag } from "next/cache";
import * as v from "valibot";

import type { PermissionKey } from "@/lib/supabase/blocks.generated";

import { organizationSnapshotTag } from "@/features/user/permission-snapshot";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Key = v.pipe(
  v.string(),
  v.regex(/^[a-z_]+(\.[a-z_]+)+$/),
  // SAFETY: set_permission_override refuses a key outside the catalog.
  v.transform((key) => key as PermissionKey),
);

/**
 * Grants (`true`) or denies (`false`) one key to a role in the active
 * organization, or restores the role's default (`null`), through the
 * permissions block's `set_permission_override`. It checks `roles.manage`, the
 * role and the key in SQL. Every member's permission snapshot in the
 * organization expires, since their role's keys changed.
 */
export const setPermissionOverride = bsb.action(
  {
    input: v.object({
      roleId: v.pipe(v.string(), v.minLength(1)),
      permission: Key,
      granted: v.nullable(v.boolean()),
    }),
    requireTenant: true,
  },
  async ({ roleId, permission, granted }, { tenant, db, auth }) => {
    const role = await db.permissions.setOverride(roleId, permission, granted);

    if (!role.ok) {
      return role;
    }

    updateTag(organizationSnapshotTag(tenant));
    await refreshCaller(auth);

    return ok(role.data.permissions);
  },
);
