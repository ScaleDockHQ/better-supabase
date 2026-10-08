import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
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
  InboxMessage,
  InboxRow,
  MessageAttachment,
  MessageTemplate,
  StoredInboundEvent,
} from "./types.ts";

import {
  type BlockTemporalOptions,
  applyTemporal,
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  instantArg,
  isRecord,
  recordOf,
  seconds,
  textOf,
  toInstant,
} from "../shared.ts";
import {
  contactOf,
  conversationOf,
  conversationsOf,
  countsOf,
  eventsOf,
  inboundOf,
  inboxOf,
  messageOf,
  messagesOf,
  reactionsOf,
  storedEventsOf,
  templateOf,
} from "./rows.ts";

export interface InboxOptions extends BlockTemporalOptions {
  /**
   * `sqlTransport(postgres.asUser(claims))` or `rpcTransport(supabase)` for a
   * member or a contact; over the service role for webhooks and workers.
   */
  readonly transport: BlockTransport;
  /** `sql.modules.inbox.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface CreateInboxInput {
  readonly tenant: string;
  readonly name: string;
  readonly channel?: InboxChannel;
  /** The channel's address: a phone number, a Slack team id, an email. */
  readonly address?: string;
  readonly botMode?: BotMode;
  /** `widget: true` lets signed-in visitors open conversations in an in-app inbox. */
  readonly settings?: Readonly<Record<string, unknown>>;
}

export interface InboxPatch {
  readonly name?: string;
  readonly botMode?: BotMode;
  readonly settings?: Readonly<Record<string, unknown>>;
  readonly address?: string | null;
  readonly installationId?: string | null;
  readonly archived?: boolean;
}

export interface ContactInput {
  readonly id?: string;
  readonly userId?: string;
  readonly name?: string;
  readonly email?: string;
  readonly phone?: string;
  readonly avatarUrl?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** The contact's id on a channel, such as a WhatsApp number. */
  readonly identity?: { readonly channel: string; readonly externalId: string };
}

export interface MessageInput {
  readonly body: string;
  /** `note` is an internal note only staff see. */
  readonly kind?: "message" | "note";
  readonly format?: "text" | "markdown";
  readonly attachments?: readonly MessageAttachment[];
  /** User ids; those who cannot read the inbox are dropped. */
  readonly mentions?: readonly string[];
  readonly replyTo?: string;
  readonly externalId?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** For the service: who writes. Defaults to `bot`. */
  readonly authorType?: "contact" | "bot" | "system";
  /** For the service: the caller posts to the channel itself, so no outbound job is queued. */
  readonly deliveredByCaller?: boolean;
}

export interface StartConversationInput {
  /** A contact id or the fields to find or create one. Ignored for a widget visitor. */
  readonly contact?: string | ContactInput;
  readonly subject?: string;
  readonly priority?: ConversationPriority;
  readonly botMode?: BotMode;
  /** The Chat SDK thread id. Defaults to `inbox:<conversation id>`. */
  readonly threadId?: string;
  readonly assigneeId?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly message?: string | MessageInput;
}

export interface InboundInput {
  readonly inboxId: string;
  readonly threadId: string;
  readonly contact: ContactInput & {
    /** Shorthand for `identity` on the inbox's channel. */
    readonly externalId?: string;
  };
  readonly message: Omit<MessageInput, "kind" | "authorType">;
  readonly subject?: string;
  /** `outbound` records a message sent from the platform by someone else. */
  readonly direction?: "inbound" | "outbound";
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface ConversationFilter {
  readonly inboxId?: string;
  /** Defaults to `open`. */
  readonly status?: ConversationStatus | "all";
  readonly assignee?: "me" | "unassigned" | (string & {});
  readonly teamId?: string;
  readonly contactId?: string;
  readonly search?: string;
  /** The last item of the previous page. */
  readonly before?: Pick<Conversation, "id" | "lastMessageAt">;
  /** Up to 200. Defaults to 50. */
  readonly limit?: number;
}

export interface TemplateInput {
  readonly name: string;
  readonly channel: string;
  readonly body: string;
  readonly language?: string;
  readonly inboxId?: string;
  readonly variables?: readonly string[];
  readonly externalId?: string;
}

/** The `inbox` SQL module as typed calls. */
export interface Inbox {
  readonly inboxes: {
    create(input: CreateInboxInput): AsyncResult<InboxRow>;
    update(id: string, patch: InboxPatch): AsyncResult<InboxRow>;
    /** `null` removes the member. */
    setMember(
      inboxId: string,
      userId: string,
      role: "agent" | "lead" | null,
    ): AsyncResult<boolean>;
    createTeam(
      tenant: string,
      name: string,
    ): AsyncResult<{ readonly id: string; readonly name: string }>;
    setTeamMember(
      teamId: string,
      userId: string,
      present?: boolean,
    ): AsyncResult<boolean>;
  };
  readonly contacts: {
    /** Finds the contact by id, identity, user or email, filling in what is missing. */
    upsert(tenant: string, input: ContactInput): AsyncResult<Contact>;
  };
  readonly conversations: {
    open(
      inboxId: string,
      input?: StartConversationInput,
    ): AsyncResult<Conversation>;
    list(
      tenant: string | null,
      filter?: ConversationFilter,
    ): AsyncResult<readonly Conversation[]>;
    get(conversationId: string): AsyncResult<Conversation | null>;
    assign(
      conversationId: string,
      to: {
        readonly assigneeId: string | null;
        readonly teamId?: string | null;
      },
    ): AsyncResult<Conversation>;
    setStatus(
      conversationId: string,
      status: ConversationStatus,
      options?: { readonly snoozedUntil?: Temporal.Instant },
    ): AsyncResult<Conversation>;
    snooze(
      conversationId: string,
      until: Temporal.Instant,
    ): AsyncResult<Conversation>;
    resolve(conversationId: string): AsyncResult<Conversation>;
    reopen(conversationId: string): AsyncResult<Conversation>;
    /** Hands a bot conversation to staff (`bot_mode = 'human'`) and tells them. */
    handoff(conversationId: string, reason?: string): AsyncResult<Conversation>;
    setBotMode(
      conversationId: string,
      mode: BotMode,
      reason?: string,
    ): AsyncResult<Conversation>;
    markRead(conversationId: string): AsyncResult<Temporal.Instant>;
    /** A typing ping on `inbox:<id>`; the service names the bot in `actor`. */
    typing(
      conversationId: string,
      typing?: boolean,
      actor?: string,
    ): AsyncResult<boolean>;
    events(conversationId: string): AsyncResult<readonly ConversationEvent[]>;
    counts(tenant: string): AsyncResult<InboxCounts>;
  };
  readonly messages: {
    send(
      conversationId: string,
      input: MessageInput,
    ): AsyncResult<InboxMessage>;
    /** An internal note only staff see. */
    note(
      conversationId: string,
      body: string,
      input?: Pick<MessageInput, "mentions" | "attachments" | "format">,
    ): AsyncResult<InboxMessage>;
    list(
      conversationId: string,
      options?: { readonly before?: Temporal.Instant; readonly limit?: number },
    ): AsyncResult<readonly InboxMessage[]>;
    get(messageId: string): AsyncResult<InboxMessage | null>;
    edit(messageId: string, body: string): AsyncResult<InboxMessage>;
    /** Leaves a tombstone with an empty body. */
    remove(messageId: string): AsyncResult<InboxMessage>;
    react(
      messageId: string,
      emoji: string,
      options?: { readonly present?: boolean; readonly actor?: string },
    ): AsyncResult<Readonly<Record<string, readonly string[]>>>;
  };
  readonly deliveries: {
    /** Service only: after posting a message on its channel. */
    record(input: {
      readonly messageId: string;
      readonly channel: string;
      readonly externalId?: string;
      readonly status?: DeliveryStatus;
      readonly error?: string;
    }): AsyncResult<void>;
    /** Service only: a status callback; returns how many deliveries moved. */
    setStatus(input: {
      readonly channel: string;
      readonly externalId: string;
      readonly status: DeliveryStatus;
      readonly error?: string;
    }): AsyncResult<number>;
  };
  readonly templates: {
    upsert(tenant: string, input: TemplateInput): AsyncResult<MessageTemplate>;
    delete(id: string): AsyncResult<boolean>;
  };
  /** Service only: channel messages, the webhook store and its sweeps. */
  readonly inbound: {
    /** A message that arrived on a channel: finds or opens the thread's conversation. */
    record(input: InboundInput): AsyncResult<InboundResult>;
    store(input: {
      readonly adapter: string;
      readonly body: string;
      readonly externalId?: string;
      readonly headers?: Readonly<Record<string, string>>;
      readonly inboxId?: string;
      readonly tenant?: string;
    }): AsyncResult<{ readonly id: string; readonly duplicate: boolean }>;
    setStatus(
      id: string,
      status: "processing" | "processed" | "ignored" | "failed",
      error?: string,
    ): AsyncResult<boolean>;
    pending(options?: {
      readonly limit?: number;
      readonly maxAttempts?: number;
    }): AsyncResult<readonly StoredInboundEvent[]>;
    purge(options?: {
      readonly olderThan?: number | string;
      readonly batch?: number;
    }): AsyncResult<number>;
  };
  /** Service only: reopens snoozed conversations whose time came. */
  wakeSnoozed(): AsyncResult<number>;
}

export function contactArg(
  input: ContactInput & { readonly externalId?: string },
): Record<string, unknown> {
  return {
    id: input.id,
    user_id: input.userId,
    name: input.name,
    email: input.email,
    phone: input.phone,
    avatar_url: input.avatarUrl,
    metadata: input.metadata,
    external_id: input.externalId,
    identity: input.identity && {
      channel: input.identity.channel,
      external_id: input.identity.externalId,
    },
  };
}

export function messageArg(input: MessageInput): Record<string, unknown> {
  return {
    body: input.body,
    kind: input.kind,
    format: input.format,
    attachments: input.attachments?.map((file) => ({
      path: file.path,
      url: file.url,
      name: file.name,
      content_type: file.contentType,
      size: file.size,
    })),
    mentions: input.mentions,
    reply_to: input.replyTo,
    external_id: input.externalId,
    metadata: input.metadata,
    author_type: input.authorType,
    delivered_by_caller: input.deliveredByCaller,
  };
}

/** Drops `undefined` so the jsonb input only carries what the caller set. */
export function compact(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === undefined) continue;
    out[key] =
      isRecord(item) && Object.getPrototypeOf(item) === Object.prototype
        ? compact(item)
        : item;
  }
  return out;
}

/**
 * The `inbox` SQL module as typed calls: inboxes, contacts, conversations,
 * messages and notes, assignment, bot hand-off, read state, deliveries and
 * the stored webhook events. The database checks every permission.
 */
export function createInbox(options: InboxOptions): Inbox {
  applyTemporal(options);
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );
  const startArg = (input: StartConversationInput): Record<string, unknown> =>
    compact({
      contact:
        typeof input.contact === "string"
          ? input.contact
          : input.contact && contactArg(input.contact),
      subject: input.subject,
      priority: input.priority,
      bot_mode: input.botMode,
      thread_id: input.threadId,
      assignee_id: input.assigneeId,
      metadata: input.metadata,
      message:
        typeof input.message === "string"
          ? input.message
          : input.message && messageArg(input.message),
    });
  const setStatus = (
    conversationId: string,
    status: ConversationStatus,
    snoozedUntil?: Temporal.Instant,
  ): AsyncResult<Conversation> =>
    call(
      "set_conversation_status",
      {
        conversation: conversationId,
        status,
        snoozed_until: instantArg(snoozedUntil),
      },
      conversationOf,
    );
  const setBotMode = (
    conversationId: string,
    mode: BotMode,
    reason?: string,
  ): AsyncResult<Conversation> =>
    call(
      "set_bot_mode",
      { conversation: conversationId, mode, reason },
      conversationOf,
    );
  const send = (
    conversationId: string,
    input: MessageInput,
  ): AsyncResult<InboxMessage> =>
    call(
      "send_message",
      { conversation: conversationId, input: compact(messageArg(input)) },
      messageOf,
    );

  return {
    inboxes: {
      create: (input) =>
        call(
          "create_inbox",
          {
            tenant: input.tenant,
            name: input.name,
            channel: input.channel,
            settings: input.settings,
            bot_mode: input.botMode,
            address: input.address,
          },
          inboxOf,
        ),
      update: (id, patch) =>
        call(
          "update_inbox",
          {
            inbox: id,
            patch: compact({
              name: patch.name,
              bot_mode: patch.botMode,
              settings: patch.settings,
              address: patch.address,
              installation_id: patch.installationId,
              archived: patch.archived,
            }),
          },
          inboxOf,
        ),
      setMember: (inboxId, userId, role) =>
        call(
          "set_inbox_member",
          { inbox: inboxId, member: userId, role },
          (value) => value === true,
        ),
      createTeam: (tenant, name) =>
        call("create_inbox_team", { tenant, name }, (value) => {
          const row = recordOf(value, "create_inbox_team");
          return { id: textOf(row["id"]), name: textOf(row["name"]) };
        }),
      setTeamMember: (teamId, userId, present = true) =>
        call(
          "set_inbox_team_member",
          { team: teamId, member: userId, present },
          (value) => value === true,
        ),
    },
    contacts: {
      upsert: (tenant, input) =>
        call(
          "upsert_contact",
          { tenant, input: compact(contactArg(input)) },
          contactOf,
        ),
    },
    conversations: {
      open: (inboxId, input = {}) =>
        call(
          "start_conversation",
          { inbox: inboxId, input: startArg(input) },
          conversationOf,
        ),
      list: (tenant, filter = {}) =>
        call(
          "list_conversations",
          {
            tenant,
            filter: compact({
              inbox_id: filter.inboxId,
              status: filter.status,
              assignee: filter.assignee,
              team_id: filter.teamId,
              contact_id: filter.contactId,
              search: filter.search,
              before: filter.before && {
                id: filter.before.id,
                last_message_at: filter.before.lastMessageAt?.toString(),
              },
              limit: filter.limit,
            }),
          },
          conversationsOf,
        ),
      get: (conversationId) =>
        call("get_conversation", { conversation: conversationId }, (value) =>
          value === null ? null : conversationOf(value),
        ),
      assign: (conversationId, to) =>
        call(
          "assign_conversation",
          {
            conversation: conversationId,
            assignee: to.assigneeId,
            team: to.teamId ?? null,
          },
          conversationOf,
        ),
      setStatus: (conversationId, status, statusOptions = {}) =>
        setStatus(conversationId, status, statusOptions.snoozedUntil),
      snooze: (conversationId, until) =>
        setStatus(conversationId, "snoozed", until),
      resolve: (conversationId) => setStatus(conversationId, "resolved"),
      reopen: (conversationId) => setStatus(conversationId, "open"),
      handoff: (conversationId, reason) =>
        setBotMode(conversationId, "human", reason),
      setBotMode,
      markRead: (conversationId) =>
        call(
          "mark_conversation_read",
          { conversation: conversationId },
          (value) => {
            if (typeof value !== "string" && !(value instanceof Date))
              throw new TypeError("mark_conversation_read returned no time");
            return toInstant(value);
          },
        ),
      typing: (conversationId, typing = true, actor) =>
        call(
          "set_typing",
          { conversation: conversationId, typing, actor },
          (value) => value === true,
        ),
      events: (conversationId) =>
        call(
          "list_conversation_events",
          { conversation: conversationId },
          eventsOf,
        ),
      counts: (tenant) => call("inbox_counts", { tenant }, countsOf),
    },
    messages: {
      send,
      note: (conversationId, body, input = {}) =>
        send(conversationId, { ...input, body, kind: "note" }),
      list: (conversationId, page = {}) =>
        call(
          "list_messages",
          {
            conversation: conversationId,
            before: instantArg(page.before),
            max: page.limit,
          },
          messagesOf,
        ),
      get: (messageId) =>
        call("get_message", { message: messageId }, (value) =>
          value === null ? null : messageOf(value),
        ),
      edit: (messageId, body) =>
        call("edit_message", { message: messageId, body }, messageOf),
      remove: (messageId) =>
        call("edit_message", { message: messageId, remove: true }, messageOf),
      react: (messageId, emoji, reactOptions = {}) =>
        call(
          "react_to_message",
          {
            message: messageId,
            emoji,
            present: reactOptions.present ?? true,
            actor: reactOptions.actor,
          },
          reactionsOf,
        ),
    },
    deliveries: {
      record: (input) =>
        call(
          "record_delivery",
          {
            message: input.messageId,
            channel: input.channel,
            external_id: input.externalId,
            status: input.status,
            error: input.error,
          },
          () => undefined,
        ),
      setStatus: (input) =>
        call(
          "set_delivery_status",
          {
            channel: input.channel,
            external_id: input.externalId,
            status: input.status,
            error: input.error,
          },
          Number,
        ),
    },
    templates: {
      upsert: (tenant, input) =>
        call(
          "upsert_message_template",
          {
            tenant,
            input: compact({
              name: input.name,
              channel: input.channel,
              body: input.body,
              language: input.language,
              inbox_id: input.inboxId,
              variables: input.variables,
              external_id: input.externalId,
            }),
          },
          templateOf,
        ),
      delete: (id) =>
        call(
          "delete_message_template",
          { template: id },
          (value) => value === true,
        ),
    },
    inbound: {
      record: (input) =>
        call(
          "record_inbound",
          {
            input: compact({
              inbox_id: input.inboxId,
              thread_id: input.threadId,
              contact: contactArg(input.contact),
              message: messageArg(input.message),
              subject: input.subject,
              direction: input.direction,
              metadata: input.metadata,
            }),
          },
          inboundOf,
        ),
      store: (input) =>
        call(
          "store_inbound_event",
          {
            adapter: input.adapter,
            body: input.body,
            external_id: input.externalId,
            headers: input.headers,
            inbox: input.inboxId,
            tenant: input.tenant,
          },
          (value) => {
            const row = recordOf(value, "store_inbound_event");
            return {
              id: textOf(row["id"]),
              duplicate: row["duplicate"] === true,
            };
          },
        ),
      setStatus: (id, status, error) =>
        call(
          "set_inbound_event_status",
          { event: id, status, error },
          (value) => value === true,
        ),
      pending: (pending = {}) =>
        call(
          "pending_inbound_events",
          { max: pending.limit, max_attempts: pending.maxAttempts },
          storedEventsOf,
        ),
      purge: (purge = {}) =>
        call(
          "purge_inbound_events",
          {
            older_than:
              purge.olderThan === undefined
                ? undefined
                : seconds(purge.olderThan),
            batch: purge.batch,
          },
          Number,
        ),
    },
    wakeSnoozed: () => call("wake_snoozed_conversations", {}, Number),
  };
}
