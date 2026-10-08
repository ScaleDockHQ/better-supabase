import type { Conversation, InboxMessage } from "better-supabase/blocks/inbox";

import * as v from "valibot";

/**
 * The seeded Help inbox (supabase/seed.sql): an in-app widget inbox in Acme.
 * Anyone signed in can open a conversation there; Acme's staff answer.
 */
export const HELP_INBOX_ID = "00000000-0000-4000-8000-00000000e001";

export const ConversationStatus = v.picklist([
  "open",
  "pending",
  "snoozed",
  "resolved",
  "all",
]);
export type ConversationStatus = v.InferOutput<typeof ConversationStatus>;

export const AssigneeFilter = v.picklist(["anyone", "me", "unassigned"]);
export type AssigneeFilter = v.InferOutput<typeof AssigneeFilter>;

/** A conversation as plain data, so it crosses the server boundary. */
export interface ConversationRow {
  readonly id: string;
  readonly subject: string | null;
  readonly status: Conversation["status"];
  readonly botMode: Conversation["botMode"];
  readonly assigneeId: string | null;
  readonly preview: string | null;
  readonly lastMessageAt: string | null;
  readonly unread: boolean;
  readonly contactName: string;
  readonly contactReadAt: string | null;
  readonly inboxName: string | null;
  readonly channel: string | null;
}

export function toConversationRow(conversation: Conversation): ConversationRow {
  const contact = conversation.contact;
  return {
    id: conversation.id,
    subject: conversation.subject,
    status: conversation.status,
    botMode: conversation.botMode,
    assigneeId: conversation.assigneeId,
    preview: conversation.preview,
    lastMessageAt: conversation.lastMessageAt?.toString() ?? null,
    unread: conversation.unread ?? false,
    contactName: contact?.name ?? contact?.email ?? contact?.phone ?? "",
    contactReadAt: conversation.contactReadAt?.toString() ?? null,
    inboxName: conversation.inbox?.name ?? null,
    channel: conversation.inbox?.channel ?? null,
  };
}

/** A message as plain data. */
export interface MessageRow {
  readonly id: string;
  readonly kind: InboxMessage["kind"];
  readonly authorType: InboxMessage["authorType"];
  readonly authorId: string | null;
  readonly body: string;
  readonly createdAt: string;
  readonly deleted: boolean;
  readonly delivery: string | null;
}

export function toMessageRow(message: InboxMessage): MessageRow {
  return {
    id: message.id,
    kind: message.kind,
    authorType: message.authorType,
    authorId: message.authorId,
    body: message.body,
    createdAt: message.createdAt.toString(),
    deleted: message.deletedAt !== null,
    delivery: message.delivery?.status ?? null,
  };
}
