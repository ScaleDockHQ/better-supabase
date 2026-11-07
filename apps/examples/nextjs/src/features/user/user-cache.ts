import { tagFor } from "better-supabase/next";

/** The tag of a user's snapshot entries. */
export function snapshotTag(sub: string | null): string {
  return tagFor("permissions", sub ?? "anon");
}

/** The tag of every member's snapshot in one organization. */
export function organizationSnapshotTag(organizationId: string): string {
  return tagFor("permissions", undefined, { tenant: organizationId });
}
