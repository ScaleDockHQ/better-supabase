"use server";

import type { ConversationFilter } from "better-supabase/blocks/inbox";

import { ok } from "better-supabase";
import { after } from "next/server";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import { answerHelp } from "./help-bot";
import {
  AssigneeFilter,
  ConversationStatus,
  HELP_INBOX_ID,
  toConversationRow,
  toMessageRow,
} from "./inbox-types";

const Id = v.pipe(v.string(), v.uuid());
const Body = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000));
const ConversationInput = v.object({ conversationId: Id });

/** The list for the filters, loaded again by `useInbox` after each ping. */
export const loadConversations = bs.action(
  {
    input: v.object({ status: ConversationStatus, assignee: AssigneeFilter }),
    requireTenant: true,
  },
  async ({ status, assignee }, { tenant, supabase }) => {
    const filter: ConversationFilter = { status, limit: 50 };
    const listed = await blocks(supabase).inbox.conversations.list(
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
export const loadThread = bs.action(
  { input: ConversationInput },
  async ({ conversationId }, { supabase }) => {
    const { inbox } = blocks(supabase);
    const [conversation, messages] = await Promise.all([
      inbox.conversations.get(conversationId),
      inbox.messages.list(conversationId, { limit: 100 }),
    ]);
    if (!conversation.ok) return conversation;
    if (!messages.ok) return messages;
    const { lastMessageAt, lastReadAt } = conversation.data ?? {};
    if (
      lastMessageAt &&
      (!lastReadAt || Temporal.Instant.compare(lastReadAt, lastMessageAt) < 0)
    ) {
      const read = await inbox.conversations.markRead(conversationId);
      if (!read.ok) return read;
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

/** A reply to the contact, or with `note` an internal note only staff see. */
export const reply = bs.action(
  {
    input: v.object({ conversationId: Id, body: Body, note: v.boolean() }),
  },
  async ({ conversationId, body, note }, { supabase }) => {
    const { messages } = blocks(supabase).inbox;
    const sent = note
      ? await messages.note(conversationId, body)
      : await messages.send(conversationId, { body });
    return sent.ok ? ok(sent.data.id) : sent;
  },
);

export const assign = bs.action(
  { input: v.object({ conversationId: Id, toMe: v.boolean() }) },
  async ({ conversationId, toMe }, { auth, supabase }) => {
    const assigned = await blocks(supabase).inbox.conversations.assign(
      conversationId,
      { assigneeId: toMe && auth.kind === "user" ? auth.user.id : null },
    );
    return assigned.ok ? ok(assigned.data.assigneeId) : assigned;
  },
);

/** Hands a bot conversation to staff. */
export const takeOver = bs.action(
  { input: ConversationInput },
  async ({ conversationId }, { supabase }) => {
    const changed = await blocks(supabase).inbox.conversations.handoff(
      conversationId,
      "staff took over",
    );
    return changed.ok ? ok(changed.data.botMode) : changed;
  },
);

export const setStatus = bs.action(
  {
    input: v.object({
      conversationId: Id,
      resolved: v.boolean(),
    }),
  },
  async ({ conversationId, resolved }, { supabase }) => {
    const { conversations } = blocks(supabase).inbox;
    const changed = resolved
      ? await conversations.resolve(conversationId)
      : await conversations.reopen(conversationId);
    return changed.ok ? ok(changed.data.status) : changed;
  },
);

/**
 * The Help sheet's first message: opens a conversation as the visitor, with
 * the `/assistant` bot answering until staff take over.
 */
export const askForHelp = bs.action(
  { input: v.object({ message: Body }) },
  async ({ message }, { auth, supabase }) => {
    const opened = await blocks(supabase).inbox.conversations.open(
      HELP_INBOX_ID,
      { subject: message.slice(0, 80), message, botMode: "bot" },
    );
    if (!opened.ok) return opened;
    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerHelp(supabase, userId, opened.data.id, message));
    }
    return ok(opened.data.id);
  },
);

/** The Help sheet's later messages, as the conversation's contact. */
export const sendHelp = bs.action(
  { input: v.object({ conversationId: Id, message: Body }) },
  async ({ conversationId, message }, { auth, supabase }) => {
    const sent = await blocks(supabase).inbox.messages.send(conversationId, {
      body: message,
    });
    if (!sent.ok) return sent;
    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerHelp(supabase, userId, conversationId, message));
    }
    return ok(sent.data.id);
  },
);
