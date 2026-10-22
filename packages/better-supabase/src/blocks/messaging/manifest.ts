import type { BlockOf } from "../define-block.ts";
import type { MessagingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { messagingEvents } from "./events.ts";
import { createMessaging } from "./messaging.ts";
import { messagingSqlOptions } from "./options.ts";
import { messageChangeSchema, messageInputSchema } from "./schemas.ts";

/** The `messaging` block's manifest (ADR 0029, ADR 0062). */
export const messagingBlock: BlockOf<
  "messaging",
  typeof createMessaging,
  MessagingEvents
> = defineBlock({
  name: "messaging",
  sql: ["messaging"],
  options: { messaging: messagingSqlOptions },
  events: messagingEvents,
  schemas: {
    message: { input: messageInputSchema, change: messageChangeSchema },
  },
  create: createMessaging,
  client: "messaging",
  category: "collaboration",
  recipes: [
    "channel-sidebar",
    "message-composer",
    "message-list",
    "presence-avatars",
    "thread-panel",
  ],
});
