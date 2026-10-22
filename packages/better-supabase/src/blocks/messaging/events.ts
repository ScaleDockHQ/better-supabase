import type {
  ConversationEventData,
  MessageEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `messaging` block: type to data. */
export type MessagingEvents = {
  readonly "conversation.created": ConversationEventData;
  readonly "conversation.archived": ConversationEventData;
  readonly "conversation.member_added": ConversationEventData;
  readonly "conversation.member_removed": ConversationEventData;
  readonly "message.sent": MessageEventData;
  readonly "message.edited": MessageEventData;
  readonly "message.deleted": MessageEventData;
  readonly "message.pinned": MessageEventData;
  readonly "message.resolved": MessageEventData;
};

/** The `messaging` block's event types, for its manifest and `onBlockEvent`. */
export const messagingEvents: Events<MessagingEvents> = defineEvents({
  "conversation.created": event<ConversationEventData>(),
  "conversation.archived": event<ConversationEventData>(),
  "conversation.member_added": event<ConversationEventData>(),
  "conversation.member_removed": event<ConversationEventData>(),
  "message.sent": event<MessageEventData>(),
  "message.edited": event<MessageEventData>(),
  "message.deleted": event<MessageEventData>(),
  "message.pinned": event<MessageEventData>(),
  "message.resolved": event<MessageEventData>(),
});
