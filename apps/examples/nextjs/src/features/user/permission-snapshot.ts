import "server-only";
import { cacheTag } from "next/cache";

import { bs } from "@/lib/supabase/server";

import { PERMISSIONS, type Permission, can } from "./user-permissions";

// An authorization library with its own snapshot replaces `can` here and
// keeps the `bs.cached()` call.
// See https://bettersupabase.com/docs/frameworks/next-cache-components#permission-snapshots.

/** The tag of a user's snapshot entries. */
function snapshotTag(sub: string | null): string {
  return `permissions:${sub ?? "anon"}`;
}

interface PermissionSnapshot {
  readonly permissions: readonly Permission[];
  /** Unix seconds: the snapshot is valid as long as the token it was built from. */
  readonly expiresAt: number | null;
}

/**
 * The caller's permissions, cached per user. `bs.cached()` tags the entry
 * with the session and snapshot tags, and keeps it no longer than the token
 * or the snapshot.
 */
export async function getPermissionSnapshot(): Promise<PermissionSnapshot> {
  "use cache: private";
  const { session } = await bs.cached();
  cacheTag(snapshotTag(session.kind === "user" ? session.user.id : null));
  return {
    permissions: PERMISSIONS.filter((permission) => can(session, permission)),
    expiresAt: session.kind === "user" ? session.expiresAt : null,
  };
}
