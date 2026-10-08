/** The channels an inbox can sit on. */
export type InboxChannel =
  | "in_app"
  | "email"
  | "slack"
  | "teams"
  | "discord"
  | "telegram"
  | "whatsapp"
  | "messenger"
  | "instagram"
  | "sms"
  | "github"
  | "linear"
  | "other";

/** `bot`: the bot answers; `human`: staff answer; `paused`: nobody answers. */
export type BotMode = "bot" | "human" | "paused";
export type ConversationStatus = "open" | "pending" | "snoozed" | "resolved";
export type ConversationPriority = "low" | "normal" | "high" | "urgent";
export type MessageDirection = "inbound" | "outbound";
export type MessageKind = "message" | "note";
export type AuthorType = "contact" | "agent" | "bot" | "system";
export type DeliveryStatus =
  | "queued"
  | "sent"
  | "delivered"
  | "read"
  | "failed";

export interface InboxRow {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly channel: InboxChannel;
  readonly address: string | null;
  readonly installationId: string | null;
  readonly botMode: BotMode;
  readonly settings: Readonly<Record<string, unknown>>;
  readonly createdAt: Temporal.Instant;
  readonly archivedAt: Temporal.Instant | null;
}

export interface Contact {
  readonly id: string;
  readonly tenant?: string;
  readonly userId: string | null;
  readonly name: string | null;
  readonly email: string | null;
  readonly phone: string | null;
  readonly avatarUrl: string | null;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface Conversation {
  readonly id: string;
  readonly tenant: string;
  readonly inboxId: string;
  readonly contactId: string;
  readonly subject: string | null;
  readonly status: ConversationStatus;
  readonly priority: ConversationPriority;
  readonly assigneeId: string | null;
  readonly teamId: string | null;
  readonly botMode: BotMode;
  /** The Chat SDK thread id, or `inbox:<id>` for the in-app widget. */
  readonly threadId: string;
  readonly snoozedUntil: Temporal.Instant | null;
  readonly lastMessageAt: Temporal.Instant | null;
  readonly preview: string | null;
  readonly firstResponseAt: Temporal.Instant | null;
  readonly resolvedAt: Temporal.Instant | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly createdAt: Temporal.Instant;
  readonly contact: Contact | null;
  readonly inbox: {
    readonly id: string;
    readonly name: string;
    readonly channel: InboxChannel;
  } | null;
  /** When the caller last read it. */
  readonly lastReadAt: Temporal.Instant | null;
  /** In lists: whether a message arrived after `lastReadAt`. */
  readonly unread?: boolean;
}

export interface MessageAttachment {
  readonly path?: string;
  readonly url?: string;
  readonly name?: string;
  readonly contentType?: string;
  readonly size?: number;
}

export interface MessageDelivery {
  readonly channel: string;
  readonly status: DeliveryStatus;
  readonly error: string | null;
}

export interface InboxMessage {
  readonly id: string;
  readonly conversationId: string;
  readonly direction: MessageDirection;
  readonly kind: MessageKind;
  readonly authorType: AuthorType;
  readonly authorId: string | null;
  readonly body: string;
  readonly format: "text" | "markdown";
  readonly attachments: readonly MessageAttachment[];
  /** Emoji to the actors (user ids or channel ids) who reacted. */
  readonly reactions: Readonly<Record<string, readonly string[]>>;
  readonly mentions: readonly string[];
  readonly externalId: string | null;
  readonly replyTo: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly createdAt: Temporal.Instant;
  readonly editedAt: Temporal.Instant | null;
  readonly deletedAt: Temporal.Instant | null;
  readonly delivery?: MessageDelivery | null;
}

export interface ConversationEvent {
  readonly id: string;
  readonly type: string;
  readonly actorId: string | null;
  readonly data: Readonly<Record<string, unknown>>;
  readonly createdAt: Temporal.Instant;
}

export interface InboxCounts {
  readonly open: number;
  readonly mine: number;
  readonly unassigned: number;
  readonly unread: number;
}

/** What `purgeContact` erased. */
export interface PurgedContact {
  readonly conversations: number;
  readonly messages: number;
  /** Storage paths of the erased messages' attachments, for the caller to remove. */
  readonly attachments: readonly string[];
}

export interface InboundResult {
  readonly conversationId: string;
  readonly messageId: string;
  readonly contactId: string;
  readonly tenant: string;
  /** A new conversation was opened for the thread. */
  readonly created: boolean;
  /** The message's `externalId` was already stored. */
  readonly duplicate: boolean;
}

export interface MessageTemplate {
  readonly id: string;
  readonly tenant: string;
  readonly inboxId: string | null;
  readonly name: string;
  readonly channel: string;
  readonly language: string;
  readonly body: string;
  readonly variables: readonly string[];
  /** The provider's approved template name (WhatsApp). */
  readonly externalId: string | null;
}

export interface StoredInboundEvent {
  readonly id: string;
  readonly adapter: string;
  readonly externalId: string | null;
  readonly inboxId: string | null;
  readonly tenant: string | null;
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
  readonly attempts: number;
  readonly receivedAt: Temporal.Instant;
}
