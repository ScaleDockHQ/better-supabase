"use server";

import { refresh } from "next/cache";

import { bsbCore } from "@/lib/supabase/server-core";

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
  const session = await bsbCore.claims();

  if (session.kind === "user") {
    await bsbCore.evictSession(session.user.id);
  }
}

/** `<SessionProvider onAuthzChange>` calls it after the token refresh. */
export async function refreshSessionCache(): Promise<void> {
  await bsbCore.refreshSessionCache();
}
