"use server";

import type { Result } from "better-supabase";
import type { ConversationFilter } from "better-supabase/blocks/inbox";

import { dbError, err, ok } from "better-supabase";
import { after } from "next/server";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import {
  requireCaller,
  requirePostgres,
  sqlResult,
} from "@/features/developer/postgres";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

import type { answerHelp } from "./help-bot";
import type {
  InboundEventRow,
  InboxSummary,
  MacroRow,
  TeamSummary,
} from "./inbox-types";

import {
  AssigneeFilter,
  ConversationStatus,
  HELP_INBOX_ID,
  LATER_HOURS,
  Later,
  toConversationRow,
  toDraftRow,
  toMessageRow,
  toScheduledRow,
  whatsappWindowOpen,
} from "./inbox-types";

type HelpArgs = Parameters<typeof answerHelp>;

/**
 * Loads the help bot when a member asks. The bot imports the AI SDK, the
 * assistant and the knowledge base (about 440 KB raw on the server), which
 * every page's layout would otherwise load for this one action (ADR 0542).
 */
async function answerLater(...args: HelpArgs): Promise<void> {
  const { answerHelp } = await import("./help-bot");

  await answerHelp(...args);
}

/** `ConversationFilter` without `readonly`, built field by field. */
type DraftFilter = {
  -readonly [K in keyof ConversationFilter]: ConversationFilter[K];
};

const PAGE_SIZE = 40;
const Id = v.pipe(v.string(), v.uuid());
const Body = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000));
const ConversationInput = v.object({ conversationId: Id });

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * The simulator adapter's outbound side: a reply on a channel inbox is marked
 * delivered, with a made-up platform id, so the thread shows what a real
 * adapter reports. A deployment with a Slack, WhatsApp or email adapter drains
 * the `inbox_outbound` jobs with `deliver` instead.
 */
async function simulateDelivery(
  db: Db,
  conversationId: string,
  messageId: string,
): Promise<void> {
  const conversation = await db.inbox.conversations.get(conversationId);
  const channel = conversation.ok ? conversation.data?.inbox?.channel : null;

  if (!channel || channel === "in_app") {
    return;
  }

  await bsb
    .admin()
    .inbox.deliveries.record({
      messageId,
      channel,
      externalId: `sim-${messageId}`,
      status: "delivered",
    });
}

function laterInstant(later: Later): Temporal.Instant {
  return Temporal.Now.instant().add({ hours: LATER_HOURS[later] });
}

const Cursor = v.object({ id: Id, lastMessageAt: v.nullable(v.string()) });

/**
 * The queue for the filters, newest activity first: search, status, assignee
 * and channel run in the database. `cursor` is the last row of the previous
 * page. `useInbox` loads it again after each Realtime ping.
 */
export const loadConversations = bsb.action(
  {
    input: v.object({
      status: ConversationStatus,
      assignee: AssigneeFilter,
      channel: v.optional(v.string(), ""),
      q: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(200)), ""),
      cursor: v.optional(Cursor),
    }),
    requireTenant: true,
  },
  async ({ status, assignee, channel, q, cursor }, { tenant, db }) => {
    const filter: DraftFilter = { status, limit: PAGE_SIZE };

    if (assignee !== "anyone") {
      filter.assignee = assignee;
    }

    if (channel !== "") {
      filter.inboxId = channel;
    }

    if (q !== "") {
      filter.search = q;
    }

    if (cursor !== undefined) {
      filter.cursor = {
        id: cursor.id,
        lastMessageAt:
          cursor.lastMessageAt === null
            ? null
            : Temporal.Instant.from(cursor.lastMessageAt),
      };
    }

    const listed = await db.inbox.conversations.list({ tenant, filter });

    return listed.ok ? ok(listed.data.map(toConversationRow)) : listed;
  },
);

/**
 * Reads a module table the Data API doesn't expose, as the caller, so the
 * table's row level security still decides what comes back.
 */
async function queryAsCaller<T extends object>(
  session: Parameters<typeof requireCaller>[0],
  sql: string,
  params: unknown[] = [],
): Promise<Result<readonly T[]>> {
  const caller = requireCaller(session);

  if (!caller.ok) {
    return caller;
  }

  const { connection, claims } = caller.data;

  return sqlResult(() => connection.asUser(claims).queryRaw<T>(sql, params));
}

/** The channel accounts of the organization, for the queue's channel filter. */
export const loadInboxes = bsb.action(
  { requireTenant: true, permission: "inbox.read" },
  async (_input, { session }) =>
    queryAsCaller<InboxSummary>(
      session,
      `select id, name, channel from better_supabase.inboxes
       where archived_at is null order by name`,
    ),
);

/** The canned replies of the organization (macros), for the composer. */
export const loadMacros = bsb.action(
  { requireTenant: true, permission: "inbox.read" },
  async (_input, { session }) =>
    queryAsCaller<MacroRow>(
      session,
      `select id, name, channel, body from better_supabase.inbox_message_templates
       order by name`,
    ),
);

/** The caller's draft on the conversation and the AI drafts for the team. */
export const loadDrafts = bsb.action(
  { input: ConversationInput },
  async ({ conversationId }, { db }) => {
    const listed = await db.inbox.drafts.list(conversationId);

    return listed.ok ? ok(listed.data.map(toDraftRow)) : listed;
  },
);

/** Sends a draft as the caller, with the edited text. */
export const sendDraft = bsb.action(
  { input: v.object({ draftId: Id, body: Body }) },
  async ({ draftId, body }, { db }) => {
    const sent = await db.inbox.drafts.send({ draftId, edits: { body } });

    return sent.ok ? ok(sent.data.id) : sent;
  },
);

export const discardDraft = bsb.action(
  { input: v.object({ draftId: Id }) },
  async ({ draftId }, { db }) => db.inbox.drafts.discard(draftId),
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
      inbox.messages.list({ conversationId, limit: 100 }),
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

/**
 * Keeps the unsent reply as the caller's draft on the conversation, so it
 * survives a reload; sending the reply leaves the draft to be replaced.
 */
export const saveDraft = bsb.action(
  { input: v.object({ conversationId: Id, body: Body, note: v.boolean() }) },
  async ({ conversationId, body, note }, { db }) => {
    const saved = await db.inbox.drafts.upsert({
      conversationId,
      input: { body, kind: note ? "note" : "message" },
    });

    return saved.ok ? ok(saved.data.id) : saved;
  },
);

/** A reply to the contact, or with `note` an internal note only staff see. */
export const reply = bsb.action(
  {
    input: v.object({
      conversationId: Id,
      body: Body,
      note: v.boolean(),
      // Teammates named in an internal note; they are notified.
      mentions: v.optional(v.pipe(v.array(Id), v.maxLength(20)), []),
    }),
    permission: "inbox.reply",
  },
  async ({ conversationId, body, note, mentions }, { db }) => {
    const { messages } = db.inbox;

    const sent = note
      ? await messages.note({ conversationId, body, input: { mentions } })
      : await messages.send({ conversationId, input: { body } });

    if (!sent.ok) {
      return sent;
    }

    if (!note) {
      await simulateDelivery(db, conversationId, sent.data.id);
    }

    return ok(sent.data.id);
  },
);

/** Returns a bot conversation to the bot, or pauses the bot. */
export const setBotMode = bsb.action(
  {
    input: v.object({
      conversationId: Id,
      mode: v.picklist(["bot", "human", "paused"]),
    }),
    permission: "inbox.assign",
  },
  async ({ conversationId, mode }, { db }) => {
    const changed = await db.inbox.conversations.setBotMode({
      conversationId,
      mode,
      reason: "set from the inbox",
    });

    return changed.ok ? ok(changed.data.botMode) : changed;
  },
);

export const assign = bsb.action(
  { input: v.object({ conversationId: Id, toMe: v.boolean() }) },
  async ({ conversationId, toMe }, { auth, db }) => {
    const assigned = await db.inbox.conversations.assign({
      conversationId,
      to: { assigneeId: toMe && auth.kind === "user" ? auth.user.id : null },
    });

    return assigned.ok ? ok(assigned.data.assigneeId) : assigned;
  },
);

/** The active teams of the organization, for the team queue. */
export const loadTeams = bsb.action(
  { requireTenant: true, permission: "inbox.read" },
  async (_input, { session }) =>
    queryAsCaller<TeamSummary>(
      session,
      `select id, name from better_supabase.teams
       where status = 'active' order by name`,
    ),
);

/** Puts the conversation in a team's queue, or takes it out of one. */
export const assignTeam = bsb.action(
  {
    input: v.object({ conversationId: Id, teamId: v.nullable(Id) }),
    permission: "inbox.assign",
  },
  async ({ conversationId, teamId }, { db }) => {
    const assigned = await db.inbox.conversations.assign({
      conversationId,
      to: { assigneeId: null, teamId },
    });

    return assigned.ok ? ok(assigned.data.teamId) : assigned;
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
    const changed = await db.inbox.conversations.snooze({
      conversationId,
      until: laterInstant(until),
    });

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
    const scheduled = await db.inbox.messages.schedule({
      conversationId,
      input: { body },
      at: laterInstant(at),
    });

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
    const opened = await db.inbox.conversations.open({
      inboxId: HELP_INBOX_ID,
      input: { subject: message.slice(0, 80), message, botMode: "bot" },
    });

    if (!opened.ok) {
      return opened;
    }

    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerLater(supabase, userId, opened.data.id, message));
    }

    return ok(opened.data.id);
  },
);

/** The Help sheet's later messages, as the conversation's contact. */
export const sendHelp = bsb.action(
  { input: v.object({ conversationId: Id, message: Body }) },
  async ({ conversationId, message }, { auth, db, supabase }) => {
    const sent = await db.inbox.messages.send({
      conversationId,
      input: { body: message },
    });

    if (!sent.ok) {
      return sent;
    }

    if (auth.kind === "user") {
      const userId = auth.user.id;
      after(() => answerLater(supabase, userId, conversationId, message));
    }

    return ok(sent.data.id);
  },
);

/**
 * The simulator: a message that arrives on any channel inbox, as the platform's
 * webhook would record it. The same contact on the same inbox continues one
 * thread, so a test can hold a whole conversation without an external account.
 */
export const simulateInbound = bsb.action(
  {
    input: v.object({
      inboxId: Id,
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
      address: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      subject: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(200))),
      body: Body,
    }),
    requireTenant: true,
    permission: "inbox.manage",
  },
  async ({ inboxId, name, address, subject, body }, { session }) => {
    // Row level security shows the caller only inboxes of their organization,
    // so the service call below never writes into another one.
    const visible = await queryAsCaller<{ id: string }>(
      session,
      "select id from better_supabase.inboxes where id = $1",
      [inboxId],
    );

    if (!visible.ok) {
      return visible;
    }

    if (visible.data.length === 0) {
      return err(
        dbError("not_found", "That inbox is not in your organization"),
      );
    }

    const key = address.toLowerCase();

    const contact = address.includes("@")
      ? { externalId: key, name, email: address }
      : { externalId: key, name, phone: address };

    const base = {
      inboxId,
      threadId: `sim:${inboxId}:${key}`,
      contact,
      message: { body },
    };

    const recorded = await bsb
      .admin()
      .inbox.inbound.record(
        subject === undefined || subject === "" ? base : { ...base, subject },
      );

    return recorded.ok ? ok(recorded.data.conversationId) : recorded;
  },
);

const BROADCAST_LIMIT = 50;

/**
 * One reply to every open conversation of a channel account, as the caller. The
 * block has no bulk send, so each conversation gets its own message and
 * delivery; `BROADCAST_LIMIT` keeps one click bounded.
 */
export const broadcast = bsb.action(
  {
    input: v.object({ inboxId: Id, body: Body }),
    requireTenant: true,
    permission: "inbox.manage",
  },
  async ({ inboxId, body }, { tenant, db }) => {
    const listed = await db.inbox.conversations.list({
      tenant,
      filter: { inboxId, status: "open", limit: BROADCAST_LIMIT },
    });

    if (!listed.ok) {
      return listed;
    }

    let sent = 0;

    for (const conversation of listed.data) {
      if (
        conversation.inbox?.channel === "whatsapp" &&
        !whatsappWindowOpen(toConversationRow(conversation), Date.now())
      ) {
        continue;
      }

      const message = await db.inbox.messages.send({
        conversationId: conversation.id,
        input: { body },
      });

      if (!message.ok) {
        return message;
      }

      await simulateDelivery(db, conversation.id, message.data.id);
      sent += 1;
    }

    return ok({ sent, skipped: listed.data.length - sent });
  },
);

/**
 * The organization's latest inbound webhook events. The table is service only,
 * so the read runs as the admin connection and keeps to the caller's own tenant
 * and its inboxes.
 */
export const loadInboundEvents = bsb.action(
  { requireTenant: true, permission: "inbox.manage" },
  async (_input, { tenant }) => {
    const connection = requirePostgres();

    if (!connection.ok) {
      return connection;
    }

    return sqlResult(() =>
      connection.data.admin.queryRaw<InboundEventRow>(
        `select e.id, e.adapter, e.status, e.error, e.attempts,
                e.received_at::text as "receivedAt"
         from better_supabase.inbox_inbound_events e
         where e.tenant_id = $1
            or e.inbox_id in (select id from better_supabase.inboxes where tenant_id = $1)
         order by e.received_at desc limit 25`,
        [tenant],
      ),
    );
  },
);

/**
 * Offers a stored event again: it becomes `failed` with no wait, so the next
 * `inbound.pending` sweep (`maintain`, every minute) replays it through the
 * handler.
 */
export const replayInboundEvent = bsb.action(
  {
    input: v.object({ eventId: Id }),
    requireTenant: true,
    permission: "inbox.manage",
  },
  async ({ eventId }, { tenant }) => {
    const connection = requirePostgres();

    if (!connection.ok) {
      return connection;
    }

    const owned = await sqlResult(() =>
      connection.data.admin.queryRaw<{ id: string }>(
        `update better_supabase.inbox_inbound_events e set attempts = 0
         where e.id = $2
           and (e.tenant_id = $1
             or e.inbox_id in (select id from better_supabase.inboxes where tenant_id = $1))
         returning e.id`,
        [tenant, eventId],
      ),
    );

    if (!owned.ok) {
      return owned;
    }

    if (owned.data.length === 0) {
      return err(
        dbError("not_found", "That event is not in your organization"),
      );
    }

    return bsb
      .admin()
      .inbox.inbound.setStatus({
        id: eventId,
        status: "failed",
        error: "Replay requested from the inbox",
        retryIn: 0,
      });
  },
);
