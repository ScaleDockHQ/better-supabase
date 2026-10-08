import { tenantOf } from "better-supabase/next";
import "server-only";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import { type NotificationRow, toNotificationRow } from "./notification-types";

/** The caller's latest notifications in the active organization. */
export async function getNotifications(): Promise<readonly NotificationRow[]> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);
  if (!tenant) return [];
  const items = await blocks(supabase)
    .notifications.list({ tenant, limit: 20 })
    .orThrow();
  return items.map(toNotificationRow);
}
