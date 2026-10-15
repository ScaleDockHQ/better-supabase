import type { BlockOf } from "../define-block.ts";
import type { InboxEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { inboxEvents } from "./events.ts";
import { createInbox } from "./inbox.ts";

/** The `inbox` block's manifest (ADR 0029). */
export const inboxBlock: BlockOf<"inbox", typeof createInbox, InboxEvents> =
  defineBlock({
    name: "inbox",
    sql: ["inbox", "chat-sdk-state"],
    options: {
      inbox: optionKeys([
        "topic",
        "bucket",
        "maxBodyLength",
        "botQueue",
        "outboundQueue",
        "notify",
      ]),
    },
    events: inboxEvents,
    create: createInbox,
    client: "inbox",
    category: "collaboration",
  });
