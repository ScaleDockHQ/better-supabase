import type { BlockOf } from "../define-block.ts";
import type { InboxEvents } from "./events.ts";

import { blockLink } from "../composition.ts";
import { defineBlock } from "../define-block.ts";
import { INBOX_AUTOMATIONS } from "./automations.ts";
import { inboxEvents } from "./events.ts";
import { createInbox } from "./inbox.ts";
import { inboxSqlOptions } from "./options.ts";

/** The `inbox` block's manifest (ADR 0029). */
export const inboxBlock: BlockOf<"inbox", typeof createInbox, InboxEvents> =
  defineBlock({
    name: "inbox",
    sql: ["inbox", "chat-sdk-state"],
    options: { inbox: inboxSqlOptions },
    events: inboxEvents,
    create: createInbox,
    client: "inbox",
    category: "messaging",
    entities: {
      inbox: {
        mutability: "editable",
        emits: { create: false, update: false },
      },
    },
    links: [
      blockLink(
        "fromConversation",
        "conversion",
        "inbox",
        "tasks",
        "task",
        "tasks.from_conversation",
      ),
      blockLink("contact", "reference", "inbox", "contacts", "person"),
    ],
    concerns: ["lifecycle"],
    description:
      "Conversations with contacts across the in-app widget and chat channels, on the messaging core: inboxes, members and teams, contacts who are people of the contacts block, messages and internal notes with scanned files, mentions, assignment, bot hand-off, read state, delivery status, stored webhook events, message templates, scheduled replies and reply drafts, including ai drafts staff review. Staff read with inbox.read; contacts read their own conversations without the notes; Realtime pings carry ids only.",
    recipes: ["inbox-threads"],
    automations: INBOX_AUTOMATIONS,
  });
