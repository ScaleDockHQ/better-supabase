import "server-only";
import { refresh } from "next/cache";

import { bsb } from "@/lib/supabase/server";

/**
 * Re-renders the caller's page after a mutation, with fresh `'use cache:
 * private'` entries. A production server keeps those entries across requests
 * until they go stale, so `refresh()` alone renders the old data again.
 * `bsb.cached()` tags each entry with the caller's session, which
 * `evictSession` expires (and re-renders the page). Other members see the
 * change once their entries go stale.
 */
export async function refreshCaller(auth: {
  readonly kind: string;
  readonly user?: { readonly id: string } | null;
}): Promise<void> {
  if (auth.kind === "user" && auth.user) {
    await bsb.evictSession(auth.user.id);

    return;
  }

  refresh();
}
