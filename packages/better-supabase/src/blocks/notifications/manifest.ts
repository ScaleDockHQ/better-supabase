import type { BlockOf } from "../define-block.ts";
import type { NotificationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
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
  options: {
    notifications: notificationsSqlOptions,
  },
  events: notificationsEvents,
  provides: {
    notifier: (client) => client,
  },
  create: createNotifications,
  client: "notifications",
  category: "messaging",
  recipes: ["notification-bell", "notification-list"],
});
