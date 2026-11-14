import type { BlockOf } from "../define-block.ts";
import type { NotificationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { OFFLINE_RULES } from "../offline-rules.ts";
import { notificationsEvents } from "./events.ts";
import { createNotifications } from "./notifications.ts";
import { notificationsSqlOptions } from "./options.ts";

/** The `notifications` block's manifest (ADR 0029). */
export const notificationsBlock: BlockOf<
  "notifications",
  typeof createNotifications,
  NotificationsEvents,
  Record<never, never>,
  "notifier"
> = defineBlock({
  name: "notifications",
  sql: ["notifications"],
  options: { notifications: notificationsSqlOptions },
  events: notificationsEvents,
  provides: { notifier: (client) => client },
  create: createNotifications,
  client: "notifications",
  category: "messaging",
  entities: {
    notification: {
      mutability: "state-machine",
      emits: { create: true },
      offline: OFFLINE_RULES.notifications,
    },
  },
  description:
    "In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.",
  recipes: ["notification-bell", "notification-list"],
});
