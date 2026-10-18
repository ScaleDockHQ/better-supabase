import type { BlockOf } from "../define-block.ts";
import type { InboxEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { inboxEvents } from "./events.ts";
import { createInbox } from "./inbox.ts";
import { inboxSqlOptions } from "./options.ts";

/** The `inbox` block's manifest (ADR 0029). */
export const inboxBlock: BlockOf<"inbox", typeof createInbox, InboxEvents> =
  defineBlock({
    name: "inbox",
    sql: ["inbox", "chat-sdk-state"],
    options: {
      inbox: inboxSqlOptions,
    },
    events: inboxEvents,
    create: createInbox,
    client: "inbox",
    category: "messaging",
    recipes: ["inbox-threads"],
  });
