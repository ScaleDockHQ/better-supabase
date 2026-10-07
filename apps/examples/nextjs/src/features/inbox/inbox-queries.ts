import "server-only";
import { bs } from "@/lib/supabase/server";

import { unreadSpec } from "./inbox-specs";

/**
 * The unread count plus its spec, for `useLiveCount` on the inbox page.
 * Not cached: the seed must be as fresh as the channel the client joins.
 */
export async function getUnreadSeed() {
  return bs.liveCount(unreadSpec);
}

/** The caller's latest notifications; RLS keeps it to their own rows. */
export async function getNotifications() {
  "use cache: private";
  const { db } = await bs.cached();
  return db.notifications
    .findMany({
      select: ["id", "title", "readAt", "createdAt"],
      orderBy: { createdAt: "desc" },
      limit: 20,
    })
    .orThrow();
}
