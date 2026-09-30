import "server-only";
import { next } from "@/lib/supabase.server";

import { unreadSpec } from "./inbox-specs";

/**
 * The unread count plus its spec, for `useLiveCount` on the inbox page.
 * Not cached: the seed must be as fresh as the channel the client joins.
 */
export async function getUnreadSeed() {
  return next.liveCount(unreadSpec);
}
