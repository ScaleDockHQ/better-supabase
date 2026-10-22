import "server-only";
import type { AuthSession } from "better-supabase/next";

import type { Claims, Profile } from "@/lib/claims";

import { avatarSrc } from "@/lib/buckets";
import { bsb } from "@/lib/supabase/server";

/**
 * The verified session, cached per browser session. The proxy refreshes the
 * token; this only verifies it locally against the JWKS, so it never calls the
 * Auth server. `bsb.cached()` tags the entry with the session tag, so
 * `bsb.invalidateSession` drops it, and keeps it no longer than the token. Call
 * it inside a `<Suspense>` boundary.
 */
export async function getSession(): Promise<AuthSession<Claims, Profile>> {
  "use cache: private";
  const { session } = await bsb.cached();

  return session;
}

export interface MyProfile {
  readonly fullName: string | null;
  readonly email: string | null;
  readonly username: string | null;
  /** The uploaded avatar's public URL, else the provider's picture. */
  readonly avatarUrl: string | null;
  /** The uploaded avatar's object path in the avatars bucket. */
  readonly avatarPath: string | null;
}

/**
 * The caller's row in the profiles SQL module. `bsb.invalidateSession` after a
 * profile update drops this entry with the rest of the user's cache.
 */
export async function getMyProfile(): Promise<MyProfile | null> {
  "use cache: private";
  const { db, session } = await bsb.cached();

  if (session.kind !== "user") {
    return null;
  }

  const rows = await db.$rpc("my_profile").orThrow();
  const row = rows[0];

  if (!row) {
    return null;
  }

  return {
    fullName: row.fullName,
    email: row.email,
    username: row.username,
    avatarUrl: avatarSrc(db.$buckets.avatars, row),
    avatarPath: row.avatarPath,
  };
}
