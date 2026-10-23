import type { NotificationCounts } from "better-supabase/blocks/notifications";

import {
  createNotifications,
  rpcTransport,
} from "better-supabase/blocks/notifications";
import { useAuth } from "better-supabase/react";

import { useNotifications } from "../hooks/use-notifications";
import { supabase } from "./supabase/client.native";

/** Reads counts only, so it needs no notification types. */
const notifications = createNotifications({
  transport: rpcTransport(supabase, { schema: "api" }),
  types: {},
});

async function loadCounts(): Promise<readonly NotificationCounts[]> {
  const result = await notifications.counts();

  return result.ok ? [result.data] : [];
}

const unreadOf = (counts: readonly NotificationCounts[]): number =>
  counts[0]?.unread ?? 0;

/**
 * The caller's unread count, loaded again after each broadcast on
 * `notifications:<user id>`. It is the hook the Next.js example's header badge
 * calls, imported from the same entry: the controller behind it uses the
 * client's ports, so it runs on React Native unchanged.
 */
export function useUnreadCount() {
  const auth = useAuth();
  const userId = auth.user?.id;

  const { items, count, status } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: loadCounts,
    count: unreadOf,
  });

  return { count: items === undefined ? undefined : count, status };
}
