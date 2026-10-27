import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import type { PermissionSet } from "./user-permissions";

// See https://bettersupabase.com/docs/frameworks/next-cache-components#permission-snapshots.

/** The tag of a user's snapshot entries. */
function snapshotTag(sub: string | null): string {
  return `permissions:${sub ?? "anon"}`;
}

/** The tag of every member's snapshot in one organization. */
export function organizationSnapshotTag(organizationId: string): string {
  return `permissions:organization:${organizationId}`;
}

/**
 * The caller's keys in the active organization, through the permissions block's
 * `my_permissions`: the role's catalog keys with the organization's overrides
 * applied. Cached per user for the request; `bsb.cached()` keeps the entry no
 * longer than the token. `null` without a user or an organization.
 */
export async function getPermissions(): Promise<PermissionSet | null> {
  "use cache: private";
  const { db, session } = await bsb.cached();
  const tenant = tenantOf(session);

  cacheTag(snapshotTag(session.kind === "user" ? session.user.id : null));

  if (session.kind !== "user" || tenant === undefined) {
    return null;
  }

  cacheTag(organizationSnapshotTag(tenant));

  return db.permissions.permissions().orThrow();
}
