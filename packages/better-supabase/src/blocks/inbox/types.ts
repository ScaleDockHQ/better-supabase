import type { Message } from "../messaging/messaging.ts";

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

/** A conversation's contact: a person of the contacts block. */
export interface Contact {
  /** The person's id. */
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
  /** When the contact last read it; `null` for contacts and before they read. */
  readonly contactReadAt: Temporal.Instant | null;
  /** In lists: whether a message arrived after `lastReadAt`. */
  readonly unread?: boolean;
}

/**
 * A file that arrived on a channel. The inbox stores it as a pending
 * attachment; the service fetches it with `files.pending()` and uploads it.
 */
export interface InboxFileSource {
  /** Where the channel serves it. */
  readonly url?: string;
  /** Or a Storage object the caller already wrote. */
  readonly path?: string;
  /** The bucket of `path`; files migrated from the inbox are in `inbox-files`. */
  readonly bucket?: string;
  readonly name?: string;
  readonly contentType?: string;
  readonly size?: number;
}

/** A channel file waiting to be fetched, from `files.pending()`. */
export interface PendingInboxFile {
  /** The attachment id: confirm it after the upload. */
  readonly id: string;
  readonly conversationId: string;
  readonly messageId: string;
  readonly tenant: string;
  readonly bucket: string;
  /** Where to upload it. */
  readonly path: string;
  readonly name: string;
  readonly mimeType: string | undefined;
  readonly source: InboxFileSource;
}

/** A Storage upload slot from `messages.createUpload`. */
export interface InboxUpload {
  readonly id: string;
  readonly bucket: string;
  readonly path: string;
}

export interface MessageDelivery {
  readonly channel: string;
  readonly status: DeliveryStatus;
  readonly error: string | null;
}

/**
 * A core message with the inbox's details. `kind: "note"` is an internal note
 * only staff read.
 */
export interface InboxMessage extends Message {
  readonly direction: MessageDirection;
  readonly authorType: AuthorType;
  readonly format: "text" | "markdown";
  readonly externalId: string | null;
  readonly replyTo: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  /** For staff: the first delivery on the channel. */
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
  /** The erased attachments' Storage objects, for the caller to remove. */
  readonly attachments: readonly {
    readonly bucket: string;
    readonly path: string;
  }[];
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

/** A staff reply waiting for `scheduledFor`; only its author sees it. */
export interface ScheduledInboxMessage {
  readonly id: string;
  readonly tenant: string;
  readonly conversationId: string;
  readonly authorId: string;
  readonly body: string;
  readonly format: "text" | "markdown" | null;
  readonly attachments: readonly string[];
  readonly mentions: readonly string[];
  readonly replyTo: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly scheduledFor: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
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
