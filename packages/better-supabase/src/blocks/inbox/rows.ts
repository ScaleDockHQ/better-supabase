import type {
  AuthorType,
  BotMode,
  Contact,
  Conversation,
  ConversationEvent,
  ConversationPriority,
  ConversationStatus,
  DeliveryStatus,
  InboundResult,
  PurgedContact,
  InboxChannel,
  InboxCounts,
  InboxMessage,
  InboxRow,
  MessageAttachment,
  MessageTemplate,
  StoredInboundEvent,
} from "./types.ts";

import {
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
} from "../shared.ts";

export const INBOX_CHANNELS: readonly InboxChannel[] = [
  "in_app",
  "email",
  "slack",
  "teams",
  "discord",
  "telegram",
  "whatsapp",
  "messenger",
  "instagram",
  "sms",
  "github",
  "linear",
  "other",
];

function oneOf<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fallback: T,
): T {
  const found = allowed.find((item) => item === value);
  return found ?? fallback;
}

const channelOf = (value: unknown): InboxChannel =>
  oneOf(value, INBOX_CHANNELS, "other");
const botModeOf = (value: unknown): BotMode =>
  oneOf<BotMode>(value, ["bot", "human", "paused"], "human");
const objectOf = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};
const nullableText = (value: unknown): string | null =>
  optionalText(value) ?? null;
const nullableInstant = (value: unknown): Temporal.Instant | null =>
  optionalInstant(value) ?? null;
const instant = (value: unknown, field: string): Temporal.Instant => {
  const at = optionalInstant(value);
  if (at === undefined) throw new TypeError(`${field} is missing`);
  return at;
};

export function inboxOf(value: unknown): InboxRow {
  const row = recordOf(value, "inbox");
  return {
    id: textOf(row["id"]),
    tenant: textOf(row["tenant_id"]),
    name: textOf(row["name"]),
    channel: channelOf(row["channel"]),
    address: nullableText(row["channel_address"]),
    installationId: nullableText(row["installation_id"]),
    botMode: botModeOf(row["bot_mode"]),
    settings: objectOf(row["settings"]),
    createdAt: instant(row["created_at"], "inbox.created_at"),
    archivedAt: nullableInstant(row["archived_at"]),
  };
}

export function contactOf(value: unknown): Contact {
  const row = recordOf(value, "contact");
  return {
    id: textOf(row["id"]),
    ...(row["tenant_id"] === undefined
      ? {}
      : { tenant: textOf(row["tenant_id"]) }),
    userId: nullableText(row["user_id"]),
    name: nullableText(row["name"]),
    email: nullableText(row["email"]),
    phone: nullableText(row["phone"]),
    avatarUrl: nullableText(row["avatar_url"]),
    ...(row["metadata"] === undefined
      ? {}
      : { metadata: objectOf(row["metadata"]) }),
  };
}

export function conversationOf(value: unknown): Conversation {
  const row = recordOf(value, "conversation");
  const inbox = isRecord(row["inbox"]) ? row["inbox"] : undefined;
  return {
    id: textOf(row["id"]),
    tenant: textOf(row["tenant_id"]),
    inboxId: textOf(row["inbox_id"]),
    contactId: textOf(row["contact_id"]),
    subject: nullableText(row["subject"]),
    status: oneOf<ConversationStatus>(
      row["status"],
      ["open", "pending", "snoozed", "resolved"],
      "open",
    ),
    priority: oneOf<ConversationPriority>(
      row["priority"],
      ["low", "normal", "high", "urgent"],
      "normal",
    ),
    assigneeId: nullableText(row["assignee_id"]),
    teamId: nullableText(row["team_id"]),
    botMode: botModeOf(row["bot_mode"]),
    threadId: textOf(row["thread_id"]),
    snoozedUntil: nullableInstant(row["snoozed_until"]),
    lastMessageAt: nullableInstant(row["last_message_at"]),
    preview: nullableText(row["last_message_preview"]),
    firstResponseAt: nullableInstant(row["first_response_at"]),
    resolvedAt: nullableInstant(row["resolved_at"]),
    metadata: objectOf(row["metadata"]),
    createdAt: instant(row["created_at"], "conversation.created_at"),
    contact: isRecord(row["contact"]) ? contactOf(row["contact"]) : null,
    inbox: inbox
      ? {
          id: textOf(inbox["id"]),
          name: textOf(inbox["name"]),
          channel: channelOf(inbox["channel"]),
        }
      : null,
    lastReadAt: nullableInstant(row["last_read_at"]),
    contactReadAt: nullableInstant(row["contact_read_at"]),
    ...(typeof row["unread"] === "boolean" ? { unread: row["unread"] } : {}),
  };
}

function attachmentOf(value: unknown): MessageAttachment {
  const row = objectOf(value);
  const path = optionalText(row["path"]);
  const url = optionalText(row["url"]);
  const name = optionalText(row["name"]);
  const contentType = optionalText(row["content_type"]);
  const size = row["size"];
  return {
    ...(path === undefined ? {} : { path }),
    ...(url === undefined ? {} : { url }),
    ...(name === undefined ? {} : { name }),
    ...(contentType === undefined ? {} : { contentType }),
    ...(typeof size === "number" ? { size } : {}),
  };
}

export function reactionsOf(value: unknown): Record<string, readonly string[]> {
  const out: Record<string, readonly string[]> = {};
  for (const [emoji, actors] of Object.entries(objectOf(value)))
    out[emoji] = stringsOf(actors);
  return out;
}

export function messageOf(value: unknown): InboxMessage {
  const row = recordOf(value, "message");
  const delivery = isRecord(row["delivery"]) ? row["delivery"] : undefined;
  return {
    id: textOf(row["id"]),
    conversationId: textOf(row["conversation_id"]),
    direction: row["direction"] === "outbound" ? "outbound" : "inbound",
    kind: row["kind"] === "note" ? "note" : "message",
    authorType: oneOf<AuthorType>(
      row["author_type"],
      ["contact", "agent", "bot", "system"],
      "system",
    ),
    authorId: nullableText(row["author_id"]),
    body: textOf(row["body"] ?? ""),
    format: row["format"] === "markdown" ? "markdown" : "text",
    attachments: Array.isArray(row["attachments"])
      ? row["attachments"].map(attachmentOf)
      : [],
    reactions: reactionsOf(row["reactions"]),
    mentions: stringsOf(row["mentions"]),
    externalId: nullableText(row["external_id"]),
    replyTo: nullableText(row["reply_to"]),
    metadata: objectOf(row["metadata"]),
    createdAt: instant(row["created_at"], "message.created_at"),
    editedAt: nullableInstant(row["edited_at"]),
    deletedAt: nullableInstant(row["deleted_at"]),
    ...(row["delivery"] === undefined
      ? {}
      : {
          delivery: delivery
            ? {
                channel: textOf(delivery["channel"]),
                status: deliveryStatusOf(delivery["status"]),
                error: nullableText(delivery["error"]),
              }
            : null,
        }),
  };
}

const deliveryStatusOf = (value: unknown): DeliveryStatus =>
  oneOf<DeliveryStatus>(
    value,
    ["queued", "sent", "delivered", "read", "failed"],
    "queued",
  );

export const conversationsOf = (value: unknown): readonly Conversation[] =>
  recordsOf(value, "list_conversations").map(conversationOf);

export const messagesOf = (value: unknown): readonly InboxMessage[] =>
  recordsOf(value, "list_messages").map(messageOf);

export const eventsOf = (value: unknown): readonly ConversationEvent[] =>
  recordsOf(value, "list_conversation_events").map((row) => ({
    id: textOf(row["id"]),
    type: textOf(row["type"]),
    actorId: nullableText(row["actor_id"]),
    data: objectOf(row["data"]),
    createdAt: instant(row["created_at"], "event.created_at"),
  }));

export function countsOf(value: unknown): InboxCounts {
  const row = recordOf(value, "inbox_counts");
  return {
    open: Number(row["open"] ?? 0),
    mine: Number(row["mine"] ?? 0),
    unassigned: Number(row["unassigned"] ?? 0),
    unread: Number(row["unread"] ?? 0),
  };
}

export function purgedOf(value: unknown): PurgedContact {
  const row = recordOf(value, "purge_contact");
  const paths = row["attachments"];
  return {
    conversations: Number(row["conversations"] ?? 0),
    messages: Number(row["messages"] ?? 0),
    attachments: Array.isArray(paths)
      ? paths.filter((path): path is string => typeof path === "string")
      : [],
  };
}

export function inboundOf(value: unknown): InboundResult {
  const row = recordOf(value, "record_inbound");
  return {
    conversationId: textOf(row["conversation_id"]),
    messageId: textOf(row["message_id"]),
    contactId: textOf(row["contact_id"]),
    tenant: textOf(row["tenant_id"]),
    created: row["created"] === true,
    duplicate: row["duplicate"] === true,
  };
}

export function templateOf(value: unknown): MessageTemplate {
  const row = recordOf(value, "message_template");
  return {
    id: textOf(row["id"]),
    tenant: textOf(row["tenant_id"]),
    inboxId: nullableText(row["inbox_id"]),
    name: textOf(row["name"]),
    channel: textOf(row["channel"]),
    language: textOf(row["language"]),
    body: textOf(row["body"]),
    variables: stringsOf(row["variables"]),
    externalId: nullableText(row["external_id"]),
  };
}

export const storedEventsOf = (value: unknown): readonly StoredInboundEvent[] =>
  recordsOf(value, "pending_inbound_events").map((row) => {
    const headers: Record<string, string> = {};
    for (const [key, header] of Object.entries(objectOf(row["headers"])))
      headers[key] = textOf(header);
    return {
      id: textOf(row["id"]),
      adapter: textOf(row["adapter"]),
      externalId: nullableText(row["external_id"]),
      inboxId: nullableText(row["inbox_id"]),
      tenant: nullableText(row["tenant_id"]),
      headers,
      body: textOf(row["body"]),
      attempts: Number(row["attempts"] ?? 0),
      receivedAt: instant(row["received_at"], "inbound_event.received_at"),
    };
  });
