import type { Events, InboxEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `inbox` block: type to data. */
export type InboxEvents = {
  readonly "inbox_conversation.opened": InboxEventData;
  readonly "inbox_conversation.assigned": InboxEventData;
  readonly "inbox_conversation.resolved": InboxEventData;
  readonly "inbox_conversation.reopened": InboxEventData;
  readonly "inbox_message.received": InboxEventData;
};

/** The `inbox` block's event types, for its manifest and `onBlockEvent`. */
export const inboxEvents: Events<InboxEvents> = defineEvents({
  "inbox_conversation.opened": event<InboxEventData>(),
  "inbox_conversation.assigned": event<InboxEventData>(),
  "inbox_conversation.resolved": event<InboxEventData>(),
  "inbox_conversation.reopened": event<InboxEventData>(),
  "inbox_message.received": event<InboxEventData>(),
});
