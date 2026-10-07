import "server-only";
import { type AuthSession, sessionStale } from "better-supabase/next";
import { cacheLife } from "next/cache";

import type { Claims, Profile } from "@/lib/claims";

import { bs } from "@/lib/supabase/server";

/**
 * The verified session, cached per browser session. The proxy refreshes the
 * token; this only verifies it locally against the JWKS, so it never calls
 * the Auth server. Call it inside a `<Suspense>` boundary.
 */
export async function getSession(): Promise<AuthSession<Claims, Profile>> {
  "use cache: private";
  const session = await bs.session();
  // Five minutes joins the App Shell; never past the token's expiry.
  cacheLife({ stale: sessionStale(session) });
  return session;
}

export interface MyProfile {
  readonly fullName: string | null;
  readonly email: string | null;
  readonly username: string | null;
  readonly avatarUrl: string | null;
}

/**
 * The caller's row in the profiles SQL module. `bs.invalidateSession` after
 * a profile update drops this entry with the rest of the user's cache.
 */
export async function getMyProfile(): Promise<MyProfile | null> {
  "use cache: private";
  const { db, session } = await bs.cached();
  if (session.kind !== "user") return null;
  const rows = await db.$rpc("my_profile").orThrow();
  return rows[0] ?? null;
}
