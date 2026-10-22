export {
  type Conversation,
  type ConversationAccess,
  type ConversationKind,
  type ConversationSummary,
  conversationTopic,
  createMessaging,
  type FollowTarget,
  type Message,
  type MessageCursor,
  type MessageEdit,
  type MessageEdition,
  type MessageFile,
  type MessageListOptions,
  type MessageReaction,
  type Messaging,
  type MessagingOptions,
  type NewMessage,
  type NotifyLevel,
  type OpenConversation,
  type UnreadCount,
} from "./messaging.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export {
  type MessagesActions,
  type MessagesController,
  type MessagesControllerOptions,
  type MessagesSnapshot,
  type ConversationsActions,
  type ConversationsController,
  type ConversationsControllerOptions,
  type ConversationsSnapshot,
  createMessagesController,
  createConversationsController,
  type MessageDraft,
} from "./client.ts";

export { fileAnchor, isFileAnchor } from "./anchors.ts";

export type { AnchorRegion, FileAnchor, FileAnchorAt } from "./anchors.ts";

export { messagingBlock } from "./manifest.ts";

export { messageChangeSchema, messageInputSchema } from "./schemas.ts";

export { messagingEvents } from "./events.ts";

export type { MessagingEvents } from "./events.ts";

export type { MessagingSqlOptions } from "./options.ts";
