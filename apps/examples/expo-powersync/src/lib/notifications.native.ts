import type { NotificationCounts } from "better-supabase/blocks/notifications";

import {
  createNotifications,
  createNotificationsController,
  rpcTransport,
} from "better-supabase/blocks/notifications";
import {
  powersyncNotificationsTransport,
  powersyncTopicPort,
} from "better-supabase/powersync";
import { useAuth, useBlockEnv, useController } from "better-supabase/react";

import { API_SCHEMA } from "./blocks";
import { powersync } from "./powersync/database";
import { supabase } from "./supabase/supabase.native";

/**
 * Counts read the synced notification tables, so the badge works offline. Every
 * other notification function goes to the Data API.
 */
const notifications = createNotifications({
  transport: powersyncNotificationsTransport(powersync, {
    server: rpcTransport(supabase, { schema: API_SCHEMA }),
  }),
  types: {},
});

const topic = powersyncTopicPort(powersync);

async function loadCounts(): Promise<readonly NotificationCounts[]> {
  const result = await notifications.counts();

  return result.ok ? [result.data] : [];
}

/**
 * The caller's unread count on iOS and Android, loaded again when a sync or a
 * local write changes the notification tables. The web build keeps
 * `notifications.ts`, which follows the Realtime broadcast.
 */
export function useUnreadCount() {
  const { auth } = useBlockEnv();
  const userId = useAuth().user?.id;

  const { items, count, status } = useController(
    () =>
      createNotificationsController({
        auth,
        ports: { topic },
        topic: userId ? `notifications:${userId}` : null,
        load: loadCounts,
        count: (counts) => counts[0]?.unread ?? 0,
      }),
    [auth, userId],
  ).view;

  return { count: items === undefined ? undefined : count, status };
}
