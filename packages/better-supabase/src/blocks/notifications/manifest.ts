import type { BlockOf } from "../define-block.ts";
import type { NotificationsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { notificationsEvents } from "./events.ts";
import { createNotifications } from "./notifications.ts";

/** The `notifications` block's manifest (ADR 0029). */
export const notificationsBlock: BlockOf<
  "notifications",
  typeof createNotifications,
  NotificationsEvents
> = defineBlock({
  name: "notifications",
  sql: ["notifications"],
  options: {
    notifications: optionKeys([
      "channelDefaults",
      "channels",
      "createdEvent",
      "maxRecipients",
      "priorities",
      "realtime",
      "topic",
      "updatedEvent",
    ]),
  },
  events: notificationsEvents,
  provides: {
    notifier: (client) => client,
  },
  create: createNotifications,
  client: "notifications",
  category: "collaboration",
  recipes: ["notification-bell", "notification-list"],
});
