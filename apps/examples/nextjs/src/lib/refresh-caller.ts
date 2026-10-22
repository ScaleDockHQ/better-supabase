import "server-only";
import { refresh } from "next/cache";

import { bsb } from "@/lib/supabase/server";

/**
 * Re-renders the caller's page after a mutation, with fresh `'use cache:
 * private'` entries. A production server keeps those entries across requests
 * until they go stale, so `refresh()` alone renders the old data again.
 * `bsb.cached()` tags each entry with the caller's session, which
 * `invalidateSession` expires (and re-renders the page). Other members see the
 * change once their entries go stale.
 */
export function refreshCaller(auth: {
  readonly kind: string;
  readonly user?: { readonly id: string } | null;
}): void {
  if (auth.kind === "user" && auth.user) {
    bsb.invalidateSession(auth.user.id);

    return;
  }

  refresh();
}
