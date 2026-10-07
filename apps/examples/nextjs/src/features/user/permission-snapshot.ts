import "server-only";
import { sessionStale } from "better-supabase/next";

import { bs } from "@/lib/supabase/server";

import { PERMISSIONS, type Permission, can } from "./user-permissions";

// Stand-ins for `snapshotFor` from `permdock` and `snapshotTag` and
// `cacheLifeFor` from `permdock/next`, until permdock is on npm. With
// PermDock, import those instead and keep the `bs.cached()` call.
// See https://bettersupabase.com/docs/frameworks/next-cache-components#permdock-snapshots.

/** PermDock's tag for a user's snapshot entries. */
function snapshotTag(sub: string | null): string {
  return `permdock:${sub ?? "anon"}`;
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
  const session = await bs.session();
  const snapshot: PermissionSnapshot = {
    permissions: PERMISSIONS.filter((permission) => can(session, permission)),
    expiresAt: session.kind === "user" ? session.expiresAt : null,
  };
  await bs.cached({
    tags: [snapshotTag(session.kind === "user" ? session.user.id : null)],
    life: { stale: sessionStale(session) },
  });
  return snapshot;
}
