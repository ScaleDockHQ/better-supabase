import type {
  Conversation,
  InboxChannel,
  InboxDraft,
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

/**
 * The queue's URL state (`/inbox?q=&status=&assignee=&channel=`). `channel` is
 * an inbox id: one inbox per channel, so it filters by channel and account.
 */
export const QUEUE_STATUSES = [
  "open",
  "pending",
  "snoozed",
  "resolved",
  "all",
] as const satisfies readonly ConversationStatus[];

export const QUEUE_ASSIGNEES = [
  "anyone",
  "me",
  "unassigned",
] as const satisfies readonly AssigneeFilter[];

/** Staff reply to a first message within this long, or the SLA badge warns. */
export const FIRST_RESPONSE_TARGET_MINUTES = 60;

/** WhatsApp allows free-form replies this long after the contact's last message. */
const WHATSAPP_WINDOW_HOURS = 24;

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
  readonly contactId: string;
  readonly contactEmail: string | null;
  readonly contactPhone: string | null;
  readonly inboxId: string;
  readonly inboxName: string | null;
  readonly channel: InboxChannel | null;
  readonly priority: Conversation["priority"];
  readonly firstResponseAt: string | null;
  readonly lastInboundAt: string | null;
  readonly createdAt: string;
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
    contactId: conversation.contactId,
    contactEmail: contact?.email ?? null,
    contactPhone: contact?.phone ?? null,
    inboxId: conversation.inboxId,
    inboxName: conversation.inbox?.name ?? null,
    channel: conversation.inbox?.channel ?? null,
    priority: conversation.priority,
    firstResponseAt: conversation.firstResponseAt?.toString() ?? null,
    lastInboundAt: conversation.lastInboundAt?.toString() ?? null,
    createdAt: conversation.createdAt.toString(),
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

/** An inbox of the organization: one channel account. */
export interface InboxSummary {
  readonly id: string;
  readonly name: string;
  readonly channel: string;
}

/** A canned reply from the message templates of the organization. */
export interface MacroRow {
  readonly id: string;
  readonly name: string;
  readonly channel: string;
  readonly body: string;
}

/** A reply draft: the caller's own, or one the AI suggested for the team. */
export interface DraftRow {
  readonly id: string;
  readonly body: string;
  readonly kind: "message" | "note";
  readonly source: "user" | "ai";
  readonly updatedAt: string;
}

export function toDraftRow(draft: InboxDraft): DraftRow {
  return {
    id: draft.id,
    body: draft.body,
    kind: draft.kind,
    source: draft.source,
    updatedAt: draft.updatedAt.toString(),
  };
}

/** The time since a conversation's contact last wrote, in whole minutes. */
function minutesSince(iso: string | null, now: number): number | null {
  return iso === null ? null : Math.floor((now - Date.parse(iso)) / 60_000);
}

export type SlaState = "ok" | "due" | "breached" | "met";

/** The first response SLA of a conversation, from its own timestamps. */
export function slaStateOf(row: ConversationRow, now: number): SlaState {
  if (row.firstResponseAt !== null || row.lastInboundAt === null) {
    return "met";
  }

  const waited = minutesSince(row.lastInboundAt, now) ?? 0;

  if (row.status === "resolved") {
    return "met";
  }

  if (waited >= FIRST_RESPONSE_TARGET_MINUTES) {
    return "breached";
  }

  return waited >= FIRST_RESPONSE_TARGET_MINUTES / 2 ? "due" : "ok";
}

/** True while WhatsApp still allows a free-form reply (ADR 0212). */
export function whatsappWindowOpen(row: ConversationRow, now: number): boolean {
  if (row.channel !== "whatsapp") {
    return true;
  }

  const age = minutesSince(row.lastInboundAt, now);

  return age !== null && age < WHATSAPP_WINDOW_HOURS * 60;
}
