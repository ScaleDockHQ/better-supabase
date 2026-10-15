import type {
  AiChatEventData,
  AiToolEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `ai-chat` block: type to data. */
export type AiChatEvents = {
  readonly "ai_tool_policy.set": AiToolEventData;
  readonly "ai_tool_approval.decided": AiToolEventData;
  readonly "ai_chat_message.completed": AiChatEventData;
  readonly "ai_chat.shared": AiChatEventData;
  readonly "ai_chat.share_revoked": AiChatEventData;
};

/** The `ai-chat` block's event types, for its manifest and `onBlockEvent`. */
export const aiChatEvents: Events<AiChatEvents> = defineEvents({
  "ai_tool_policy.set": event<AiToolEventData>(),
  "ai_tool_approval.decided": event<AiToolEventData>(),
  "ai_chat_message.completed": event<AiChatEventData>(),
  "ai_chat.shared": event<AiChatEventData>(),
  "ai_chat.share_revoked": event<AiChatEventData>(),
});
