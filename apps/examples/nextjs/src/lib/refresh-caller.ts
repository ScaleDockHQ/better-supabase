import "server-only";
import { refresh } from "next/cache";

import { bsbShell as bsb } from "@/lib/supabase/server-shell";

/**
 * Re-renders the caller's page after a mutation, with fresh `'use cache:
 * private'` entries. A production server keeps those entries across requests
 * until they go stale, so `refresh()` alone renders the old data again.
 *
 * With `tags`, only the entries that carry them expire (`bsb.expireTags`), then
 * the page re-renders. A domain keeps its tags in a pure `<domain>-cache.ts`
 * (ADR 0311), tags every read that its writes change, and passes the tags here,
 * so the other pages keep their entries. Without `tags` the whole session
 * expires: `bsb.cached()` tags each entry with the caller's session and
 * `evictSession` drops them all. Use that for a write that changes what other
 * domains read, and for membership, role and profile changes. Other members see
 * the change once their entries go stale.
 */
export async function refreshCaller(
  auth: {
    readonly kind: string;
    readonly user?: { readonly id: string } | null;
  },
  tags?: readonly string[],
): Promise<void> {
  if (tags !== undefined && tags.length > 0) {
    // Expires the tags for Next.js and for the kept store, so the reads that
    // `bsb.cached({ keep })` serves fill again too.
    await bsb.expireTags(tags);
    refresh();

    return;
  }

  if (auth.kind === "user" && auth.user) {
    await bsb.evictSession(auth.user.id);

    return;
  }

  refresh();
}
