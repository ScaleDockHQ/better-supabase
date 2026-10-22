import type {
  Conversation,
  InboxMessage,
  ScheduledInboxMessage,
} from "better-supabase/blocks/inbox";

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

/** When a snooze ends or a scheduled reply goes out. */
export const Later = v.picklist(["hour", "tomorrow", "week"]);

export type Later = v.InferOutput<typeof Later>;

export const LATER_HOURS: Readonly<Record<Later, number>> = {
  hour: 1,
  tomorrow: 24,
  week: 168,
};

/** A conversation as plain data, so it crosses the server boundary. */
export interface ConversationRow {
  readonly id: string;
  readonly subject: string | null;
  readonly status: Conversation["status"];
  readonly snoozedUntil: string | null;
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
    snoozedUntil: conversation.snoozedUntil?.toString() ?? null,
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
    authorId: message.authorId ?? null,
    body: message.body,
    createdAt: message.createdAt.toString(),
    deleted: message.deletedAt !== undefined,
    delivery: message.delivery?.status ?? null,
  };
}

/** The caller's reply waiting to go out, as plain data. */
export interface ScheduledRow {
  readonly id: string;
  readonly body: string;
  readonly scheduledFor: string;
}

export function toScheduledRow(scheduled: ScheduledInboxMessage): ScheduledRow {
  return {
    id: scheduled.id,
    body: scheduled.body,
    scheduledFor: scheduled.scheduledFor.toString(),
  };
}
