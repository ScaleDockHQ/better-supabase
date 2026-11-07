import "server-only";
import { permissionsOf, tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import type { PermissionSet } from "./user-permissions";

import { organizationSnapshotTag, snapshotTag } from "./user-cache";

// See https://bettersupabase.com/docs/frameworks/next-cache-components#permission-snapshots.

type CachedRequest = Awaited<ReturnType<typeof bsb.cached>>;

/**
 * The caller's keys in the active organization: the role's catalog keys with
 * the organization's overrides applied. They come from the token's
 * `permissions` claim, which the access token hook writes, and from the
 * permissions block's `my_permissions` only when the token has none for the
 * organization or marks them truncated. Cached per user for the request;
 * `bsb.cached()` keeps the entry no longer than the token. `null` without a
 * user or an organization.
 */
export async function getPermissions(): Promise<PermissionSet | null> {
  "use cache: private";

  return readPermissions(await bsb.cached());
}

/**
 * The same read for a function that already runs in a private scope and holds
 * `bsb.cached()`: it tags the surrounding entry and resolves nothing again.
 */
export async function readPermissions({
  db,
  session,
}: CachedRequest): Promise<PermissionSet | null> {
  const tenant = tenantOf(session);

  cacheTag(snapshotTag(session.kind === "user" ? session.user.id : null));

  if (session.kind !== "user" || tenant === undefined) {
    return null;
  }

  cacheTag(organizationSnapshotTag(tenant));

  const keys = permissionsOf(session, tenant);

  return keys === undefined
    ? db.permissions.permissions().orThrow()
    : { tenant, keys };
}
