"use server";

import type { ConversationFilter } from "better-supabase/blocks/inbox";

import { ok } from "better-supabase";
import { after } from "next/server";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { answerHelp } from "./help-bot";
import {
  AssigneeFilter,
  ConversationStatus,
  HELP_INBOX_ID,
  LATER_HOURS,
  Later,
  toConversationRow,
  toMessageRow,
  toScheduledRow,
} from "./inbox-types";

const Id = v.pipe(v.string(), v.uuid());
const Body = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000));
const ConversationInput = v.object({ conversationId: Id });

function laterInstant(later: Later): Temporal.Instant {
  return Temporal.Now.instant().add({ hours: LATER_HOURS[later] });
}

/** The list for the filters, loaded again by `useInbox` after each ping. */
export const loadConversations = bsb.action(
  {
    input: v.object({ status: ConversationStatus, assignee: AssigneeFilter }),
    requireTenant: true,
  },
  async ({ status, assignee }, { tenant, db }) => {
    const filter: ConversationFilter = { status, limit: 50 };

    const listed = await db.inbox.conversations.list(
      tenant,
      assignee === "anyone" ? filter : { ...filter, assignee },
    );

    return listed.ok ? ok(listed.data.map(toConversationRow)) : listed;
  },
);

/**
 * The conversation with its messages, oldest first; staff also get the notes.
 * Opening it marks it read.
 */
export const loadThread = bsb.action(
  { input: ConversationInput },
  async ({ conversationId }, { db }) => {
    const { inbox } = db;

    const [conversation, messages] = await Promise.all([
      inbox.conversations.get(conversationId),
      inbox.messages.list(conversationId, { limit: 100 }),
    ]);

    if (!conversation.ok) {
      return conversation;
    }

    if (!messages.ok) {
      return messages;
    }

    const { lastMessageAt, lastReadAt } = conversation.data ?? {};

    if (
      lastMessageAt &&
      (!lastReadAt || Temporal.Instant.compare(lastReadAt, lastMessageAt) < 0)
    ) {
      const read = await inbox.conversations.markRead(conversationId);

      if (!read.ok) {
        return read;
      }
    }

    return ok({
      conversation:
        conversation.data === null
          ? null
          : toConversationRow(conversation.data),
      messages: messages.data.map(toMessageRow),
    });
  },
);

/** One message, for the Realtime ping that names it. */
export const loadMessage = bsb.action(
  { input: v.object({ messageId: Id }) },
  async ({ messageId }, { db }) => {
    const message = await db.inbox.messages.get(messageId);

    return message.ok
      ? ok(message.data === null ? null : toMessageRow(message.data))
      : message;
  },
);

/** A reply to the contact, or with `note` an internal note only staff see. */
export const reply = bsb.action(
  { input: v.object({ conversationId: Id, body: Body, note: v.boolean() }) },
  async ({ conversationId, body, note }, { db }) => {
    const { messages } = db.inbox;

    const sent = note
      ? await messages.note(conversationId, body)
      : await messages.send(conversationId, { body });

    return sent.ok ? ok(sent.data.id) : sent;
  },
);

export const assign = bsb.action(
  { input: v.object({ conversationId: Id, toMe: v.boolean() }) },
  async ({ conversationId, toMe }, { auth, db }) => {
    const assigned = await db.inbox.conversations.assign(conversationId, {
      assigneeId: toMe && auth.kind === "user" ? auth.user.id : null,
    });

    return assigned.ok ? ok(assigned.data.assigneeId) : assigned;
  },
);

/** Hands a bot conversation to staff. */
export const takeOver = bsb.action(
  { input: ConversationInput },
  async ({ conversationId }, { db }) => {
    const changed = await db.inbox.conversations.handoff(
      conversationId,
      "staff took over",
    );

    return changed.ok ? ok(changed.data.botMode) : changed;
  },
);

export const setStatus = bsb.action(
  { input: v.object({ conversationId: Id, resolved: v.boolean() }) },
  async ({ conversationId, resolved }, { db }) => {
    const { conversations } = db.inbox;

    const changed = resolved
      ? await conversations.resolve(conversationId)
      : await conversations.reopen(conversationId);

    return changed.ok ? ok(changed.data.status) : changed;
  },
);

/** Hides the conversation until the time comes; then it opens again. */
export const snooze = bsb.action(
  { input: v.object({ conversationId: Id, until: Later }) },
  async ({ conversationId, until }, { db }) => {
    const changed = await db.inbox.conversations.snooze(
      conversationId,
      laterInstant(until),
    );

    return changed.ok ? ok(changed.data.status) : changed;
  },
);

/** The caller's replies on the conversation that wait to go out. */
export const loadScheduled = bsb.action(
  { input: ConversationInput },
  async ({ conversationId }, { db }) => {
    const listed = await db.inbox.messages.scheduled(conversationId);

    return listed.ok ? ok(listed.data.map(toScheduledRow)) : listed;
  },
);

/** A reply that goes out later, as the caller, when `publishDue` runs. */
export const scheduleReply = bsb.action(
  { input: v.object({ conversationId: Id, body: Body, at: Later }) },
  async ({ conversationId, body, at }, { db }) => {
    const scheduled = await db.inbox.messages.schedule(
      conversationId,
      { body },
      laterInstant(at),
    );

    return scheduled.ok ? ok(scheduled.data.id) : scheduled;
  },
);

export const cancelScheduled = bsb.action(
  { input: v.object({ scheduledId: Id }) },
  async ({ scheduledId }, { db }) =>
    db.inbox.messages.cancelScheduled(scheduledId),
);

/**
 * The Help sheet's first message: opens a conversation as the visitor, with the
 * `/assistant` bot answering until staff take over.
 */
export const askForHelp = bsb.action(
  { input: v.object({ message: Body }) },
  async ({ message }, { auth, db, supabase }) => {
    const opened = await db.inbox.conversations.open(HELP_INBOX_ID, {
      subject: message.slice(0, 80),
      message,
      botMode: "bot",
    });

    if (!opened.ok) {
      return opened;
    }

    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerHelp(supabase, userId, opened.data.id, message));
    }

    return ok(opened.data.id);
  },
);

/** The Help sheet's later messages, as the conversation's contact. */
export const sendHelp = bsb.action(
  { input: v.object({ conversationId: Id, message: Body }) },
  async ({ conversationId, message }, { auth, db, supabase }) => {
    const sent = await db.inbox.messages.send(conversationId, {
      body: message,
    });

    if (!sent.ok) {
      return sent;
    }

    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerHelp(supabase, userId, conversationId, message));
    }

    return ok(sent.data.id);
  },
);
