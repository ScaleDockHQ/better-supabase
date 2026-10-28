"use server";

import { refresh } from "next/cache";

import { bsb } from "@/lib/supabase/server";

/** Re-renders the islands page so a failed island reads again. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryIslands() {
  refresh();
}

/**
 * Drops the caller's cached islands in both scopes. `updateTag` reaches the
 * remote handler, so every instance that shares it misses on its next read.
 */
export async function evictMyIslands() {
  const session = await bsb.claims();

  if (session.kind === "user") {
    await bsb.evictSession(session.user.id);
  }
}

/** `<SessionProvider onAuthzChange>` calls it after the token refresh. */
export async function refreshSessionCache(): Promise<void> {
  await bsb.refreshSessionCache();
}
