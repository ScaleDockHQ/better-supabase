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
  entities: {
    message: { mutability: "editable", emits: { update: false, delete: true } },
    conversation: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Conversations and messages shared by channels, record discussions and the inbox: channels, direct and group messages, one conversation per record, members with read markers and notification levels, threads, mentions, edits with history, pins, resolved threads, scheduled sends, files and reactions. Members, the tenant or the record's readers read a conversation; Realtime pings carry ids only.",
  recipes: [
    "channel-sidebar",
    "message-composer",
    "message-list",
    "presence-avatars",
    "thread-panel",
  ],
});
