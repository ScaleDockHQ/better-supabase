export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { createInbox } from "./inbox.ts";

export type {
  ContactInput,
  ConversationFilter,
  CreateInboxInput,
  InboundInput,
  MessagePageOptions,
  Inbox,
  InboxHooks,
  InboxOptions,
  InboxPatch,
  MessageInput,
  ScheduledMessageInput,
  StartConversationInput,
  TemplateInput,
} from "./inbox.ts";

export { INBOX_CHANNELS } from "./rows.ts";

export type {
  MessageFile,
  MessageKind,
  MessageReaction,
} from "../messaging/messaging.ts";

export type {
  AuthorType,
  BotMode,
  Contact,
  Conversation,
  ConversationEvent,
  ConversationPriority,
  ConversationStatus,
  DeliveryStatus,
  InboundResult,
  InboxChannel,
  InboxCounts,
  InboxFileSource,
  InboxMessage,
  InboxRow,
  InboxUpload,
  MessageDelivery,
  MessageDirection,
  MessageTemplate,
  PendingInboxFile,
  PurgedContact,
  ScheduledInboxMessage,
  StoredInboundEvent,
} from "./types.ts";

export {
  createConversationController,
  createInboxController,
  createInboxWidgetController,
} from "./client.ts";

export type {
  ConversationActions,
  ConversationController,
  ConversationControllerOptions,
  ConversationSnapshot,
  Identified,
  InboxController,
  InboxControllerOptions,
  InboxListActions,
  InboxListSnapshot,
  InboxSource,
  InboxWidgetActions,
  InboxWidgetController,
  InboxWidgetControllerOptions,
  InboxWidgetSnapshot,
} from "./client.ts";

export { inboxBlock } from "./manifest.ts";

export { inboxEvents } from "./events.ts";

export type { InboxEvents } from "./events.ts";

export { CONVERSATION_TO_TASK, INBOX_AUTOMATIONS } from "./automations.ts";
