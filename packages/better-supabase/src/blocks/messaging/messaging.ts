import type { Author } from "../../core/block-authors.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  SummarizeOptions,
  SummarySteps,
  SummaryTarget,
  ThreadSummarizer,
  ThreadSummary,
} from "./summaries.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { editOf, messageOf, num } from "./rows.ts";
import { summarize, threadSummaryOf } from "./summaries.ts";

export { conversationTopic } from "./rows.ts";

/** What a conversation is for. */
export type ConversationKind =
  | "channel"
  | "dm"
  | "group_dm"
  | "subject"
  | "inbox";

/**
 * Who reads a conversation: its members, everyone in the tenant who holds
 * `messages.read`, or whoever reads its record.
 */
export type ConversationAccess = "members" | "tenant" | "subject";

/** How a member hears of new messages. */
export type NotifyLevel = "all" | "mentions" | "none";

const KINDS: readonly ConversationKind[] = [
  "channel",
  "dm",
  "group_dm",
  "subject",
  "inbox",
];

const ACCESS: readonly ConversationAccess[] = ["members", "tenant", "subject"];
const NOTIFY: readonly NotifyLevel[] = ["all", "mentions", "none"];

export interface Conversation {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: ConversationKind;
  readonly access: ConversationAccess;
  /** The record of a `subject` conversation. */
  readonly subject: SubjectRef | undefined;
  readonly title: string | undefined;
  readonly createdBy: string | undefined;
  readonly lastMessageAt: Temporal.Instant | undefined;
  readonly archivedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A conversation from `listConversations`, with the caller's read state. */
export interface ConversationSummary extends Conversation {
  /** Top-level messages from others since the caller's read marker. */
  readonly unread: number;
  /** How many of those mention the caller, `@channel` and `@here` included. */
  readonly mentions: number;
  readonly lastReadAt: Temporal.Instant | undefined;
  readonly notify: NotifyLevel;
}

/** A file on a message, from the `attachments` module. */
export interface MessageFile {
  readonly id: string;
  readonly name: string;
  readonly mimeType: string | undefined;
  readonly size: number | undefined;
  /** `pending` until scanned when the bucket requires a scan. */
  readonly status: string;
}

/** One emoji on a message, from the `reactions` module. */
export interface MessageReaction {
  readonly emoji: string;
  readonly count: number;
  readonly reacted: boolean;
  readonly actors: readonly string[];
}

export type MessageKind = "message" | "note";

/** A message. `F` types the extra columns the `fields` schema describes. */
export interface Message<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly conversationId: string;
  /** The message this replies to. */
  readonly parentId: string | undefined;
  /** The thread's root message; `undefined` for a top-level message. */
  readonly threadId: string | undefined;
  /** `undefined` once the author's account is deleted. */
  readonly authorId: string | undefined;
  /** The author's name and avatar, with the `profiles` module. */
  readonly author: Author | undefined;
  /** `note` is an inbox's internal note, which only its staff read. */
  readonly kind: MessageKind;
  /** Empty for a deleted message. */
  readonly body: string;
  /** The rich-text document an editor wrote, next to `body` as plain text. */
  readonly document: unknown;
  /**
   * Where on the record a top-level message points, such as a text range or a
   * field (any JSON); `undefined` without one.
   */
  readonly anchor: unknown;
  readonly mentionIds: readonly string[];
  /** `channel` or `here` when the body says `@channel` or `@here`. */
  readonly mentionScope: "channel" | "here" | undefined;
  /** A reply also shown in the conversation. */
  readonly broadcast: boolean;
  readonly replyCount: number;
  readonly lastReplyAt: Temporal.Instant | undefined;
  /** The first three people who replied. */
  readonly replyUserIds: readonly string[];
  readonly pinnedAt: Temporal.Instant | undefined;
  readonly pinnedBy: string | undefined;
  readonly resolvedAt: Temporal.Instant | undefined;
  readonly resolvedBy: string | undefined;
  /** A scheduled message has `scheduledFor` and no `sentAt` yet. */
  readonly scheduledFor: Temporal.Instant | undefined;
  readonly sentAt: Temporal.Instant | undefined;
  readonly editedAt: Temporal.Instant | undefined;
  readonly deletedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  /** Empty without the `attachments` module. */
  readonly attachments: readonly MessageFile[];
  /** Empty without the `reactions` module. */
  readonly reactions: readonly MessageReaction[];
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** An earlier version of an edited message. */
export interface MessageEdit {
  readonly id: string;
  readonly messageId: string;
  readonly body: string;
  readonly document: unknown;
  readonly editedBy: string | undefined;
  readonly editedAt: Temporal.Instant;
}

export interface NewMessage<F extends object = Record<never, never>> {
  /** Plain text; `@[Name](<user id>)` mentions a user. */
  readonly body: string;
  /** A rich-text document (any JSON); keep `body` as its plain text. */
  readonly document?: unknown;
  /** Where on the record a top-level message points (any JSON). */
  readonly anchor?: unknown;
  /** User ids, merged with the ones the body's markup mentions. */
  readonly mentionIds?: readonly string[];
  /** A reply: with one level of threads, a reply to a reply joins the root. */
  readonly parentId?: string;
  /** A reply also shown in the conversation. */
  readonly broadcast?: boolean;
  /** Sends later: with the `jobs` module, or a cron that runs `publishDue`. */
  readonly scheduledFor?: Temporal.Instant;
  /** Files the caller uploaded to the conversation (`attachments`). */
  readonly attachmentIds?: readonly string[];
  readonly fields?: Partial<F>;
}

export interface MessageEdition<F extends object = Record<never, never>> {
  readonly body: string;
  /** `null` removes the document; leaving it out keeps it. */
  readonly document?: unknown;
  readonly mentionIds?: readonly string[];
  readonly fields?: Partial<F>;
}

export interface OpenConversation {
  readonly kind: "channel" | "dm" | "group_dm" | "subject";
  /** A channel's name. */
  readonly title?: string;
  /** A channel's access: `members` (private) or `tenant`. Default `members`. */
  readonly access?: "members" | "tenant";
  /** The record of a `subject` conversation. */
  readonly subject?: SubjectRef;
  /** The members besides the caller. */
  readonly memberIds?: readonly string[];
}

/** Where a page of messages starts: a message's `sentAt` and `id`. */
export interface MessageCursor {
  readonly sentAt: Temporal.Instant;
  readonly id: string;
}

export interface MessageListOptions {
  /** The newest messages before this one. */
  readonly before?: MessageCursor;
  /** The oldest messages after this one, for catching up. */
  readonly after?: MessageCursor;
  readonly limit?: number;
}

/** A sent message that mentions a record, from `recordMentions`. */
export interface RecordMention<F extends object = Record<never, never>> {
  readonly message: Message<F>;
  /** The message's conversation: a channel, a direct message, a record's thread. */
  readonly conversation: {
    readonly id: string;
    readonly kind: ConversationKind;
    readonly title: string | undefined;
    /** The record of a `subject` conversation. */
    readonly subject: SubjectRef | undefined;
  };
}

export interface UnreadCount {
  readonly unread: number;
  readonly mentions: number;
}

/** What `follow` follows: a whole conversation or one thread. */
export type FollowTarget =
  | { readonly conversationId: string }
  | { readonly threadId: string };

/** Every method that takes no id acts in the block's `tenant`. */
export interface Messaging<F extends object = Record<never, never>> {
  /**
   * Opens a conversation. A direct or group message and a record's conversation
   * are opened once: opening again returns the same one.
   */
  open(conversation: OpenConversation): AsyncResult<Conversation>;
  /** Opens the direct (one other person) or group message with `userIds`. */
  openDirect(userIds: readonly string[]): AsyncResult<Conversation>;
  /** The conversation of a record, read by whoever reads the record. */
  openSubject(subject: SubjectRef): AsyncResult<Conversation>;
  /** Returns how many joined. Members add members; anyone joins a tenant one. */
  addMembers(
    conversationId: string,
    userIds: readonly string[],
  ): AsyncResult<number>;
  /** A member leaves, or the owner or a moderator removes them. */
  removeMember(conversationId: string, userId: string): AsyncResult<boolean>;
  archive(conversationId: string, archived?: boolean): AsyncResult<boolean>;
  /** The caller's conversations, latest message first. */
  conversations(options?: {
    readonly kinds?: readonly ConversationKind[];
    readonly limit?: number;
  }): AsyncResult<ConversationSummary[]>;
  /** Unread counts by conversation id, for the conversations with any. */
  unreadCounts(): AsyncResult<Readonly<Record<string, UnreadCount>>>;
  /** Moves the caller's read marker forward; returns where it is. */
  markRead(
    conversationId: string,
    options?: {
      readonly threadId?: string;
      readonly readAt?: Temporal.Instant;
    },
  ): AsyncResult<Temporal.Instant>;
  setNotify(conversationId: string, level: NotifyLevel): AsyncResult<boolean>;
  /** Broadcasts typing on the conversation's topic. */
  typing(conversationId: string, typing?: boolean): AsyncResult<boolean>;
  /** With the `notifications` module: hear of every message, or none. */
  follow(target: FollowTarget, following?: boolean): AsyncResult<boolean>;
  can(
    conversationId: string,
    action: "read" | "send" | "moderate",
  ): AsyncResult<boolean>;
  send(conversationId: string, message: NewMessage<F>): AsyncResult<Message<F>>;
  /** The author edits within `editWindow`; the old version is kept. */
  edit(messageId: string, edition: MessageEdition<F>): AsyncResult<Message<F>>;
  /** The author or a moderator; the message stays as a placeholder. */
  remove(messageId: string): AsyncResult<boolean>;
  pin(messageId: string, pinned?: boolean): AsyncResult<Message<F>>;
  /** Resolves a thread by its root message, or opens it again. */
  resolve(messageId: string, resolved?: boolean): AsyncResult<Message<F>>;
  /** A page of top-level messages (and broadcast replies), oldest first. */
  list(
    conversationId: string,
    options?: MessageListOptions,
  ): AsyncResult<Message<F>[]>;
  /** A thread's replies, oldest first. */
  replies(
    messageId: string,
    options?: { readonly after?: MessageCursor; readonly limit?: number },
  ): AsyncResult<Message<F>[]>;
  /** One message, or `undefined`: for a Realtime ping's id. */
  get(messageId: string): AsyncResult<Message<F> | undefined>;
  edits(messageId: string): AsyncResult<MessageEdit[]>;
  pinned(conversationId: string): AsyncResult<Message<F>[]>;
  /**
   * The sent messages that mention a record (`@[Name](subject:<type>/<id>)`),
   * newest first: its backlinks. Only the messages the caller reads, and none
   * when they can't read the record.
   */
  recordMentions(
    subject: SubjectRef,
    options?: { readonly before?: MessageCursor; readonly limit?: number },
  ): AsyncResult<RecordMention<F>[]>;
  /** The service role sends the scheduled messages that are due. */
  publishDue(limit?: number): AsyncResult<number>;
  /**
   * The summary of a thread or of a conversation's top-level messages, with
   * whether it is stale; `undefined` before the first one.
   */
  summary(target: SummaryTarget): AsyncResult<ThreadSummary | undefined>;
  /**
   * Returns the summary while it is current. Otherwise reads the newest
   * messages as the caller (internal notes left out), asks `summarizer` and
   * saves what it wrote through the `service` transport.
   */
  summarize(
    target: SummaryTarget,
    summarizer: ThreadSummarizer,
    options?: SummarizeOptions,
  ): AsyncResult<ThreadSummary>;
}

export interface MessagingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * Calls as the service role, to save thread summaries: `rpcTransport(admin)`.
   * Default `transport`.
   */
  readonly service?: BlockTransport;
  /** The module schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  /**
   * A Standard Schema for the message's extra columns
   * (`blocks.messaging.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Messaging<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function conversationOf(value: unknown): Conversation {
  const row = recordOf(value, "conversation");
  const subjectType = optionalText(row["subject_type"]);
  const subjectId = optionalText(row["subject_id"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    kind: enumOrThrow(row["kind"], KINDS, "conversation kind"),
    access: enumOrThrow(row["access"], ACCESS, "conversation access"),
    subject:
      subjectType === undefined || subjectId === undefined
        ? undefined
        : { type: subjectType, id: subjectId },
    title: optionalText(row["title"]),
    createdBy: optionalText(row["created_by"]),
    lastMessageAt: optionalInstant(row["last_message_at"]),
    archivedAt: optionalInstant(row["archived_at"]),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    updatedAt: requiredInstant(row["updated_at"], "updatedAt"),
  };
}

function summaryOf(value: unknown): ConversationSummary {
  const row = recordOf(value, "conversation");

  return {
    ...conversationOf(row),
    unread: num(row["unread"]),
    mentions: num(row["mentions"]),
    lastReadAt: optionalInstant(row["lastReadAt"]),
    notify: enumOrThrow(row["notify"] ?? "all", NOTIFY, "notify level"),
  };
}

function mentionOf(value: unknown): RecordMention {
  const row = recordOf(value, "record mention");
  const conversation = recordOf(row["conversation"], "conversation");
  const subjectType = optionalText(conversation["subject_type"]);
  const subjectId = optionalText(conversation["subject_id"]);

  return {
    message: messageOf(row["message"]),
    conversation: {
      id: textOf(conversation["id"]),
      kind: enumOrThrow(conversation["kind"], KINDS, "conversation kind"),
      title: optionalText(conversation["title"]),
      subject:
        subjectType === undefined || subjectId === undefined
          ? undefined
          : { type: subjectType, id: subjectId },
    },
  };
}

const cursorArgs = (
  prefix: "after" | "before",
  cursor: MessageCursor | undefined,
): Record<string, unknown> => ({
  [prefix]: cursor === undefined ? null : instantArg(cursor.sentAt),
  [`${prefix}_id`]: cursor?.id ?? null,
});

/**
 * The messaging block: channels, direct and group messages and record
 * conversations, with threads, mentions, edits, pins, resolved threads,
 * scheduled sends, read markers, files and reactions.
 */
export function createMessaging<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: MessagingOptions<S>): Messaging<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = options.service
    ? blockCall(options.service, options.schema, options.mappers)
    : call;

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const fields: BlockFields<F> = blockFields(options.fields, "message fields");

  const one = (fn: string, args: Record<string, unknown>) =>
    call(fn, args, messageOf).andThen(fields.row);

  const many = (fn: string, args: Record<string, unknown>) =>
    call(fn, args, (value) => recordsOf(value, fn).map(messageOf)).andThen(
      fields.rows,
    );

  const open = (conversation: OpenConversation): AsyncResult<Conversation> =>
    tenant().andThen((organizationId) =>
      call(
        "open_conversation",
        {
          tenant: organizationId,
          kind: conversation.kind,
          attrs: {
            ...(conversation.title === undefined
              ? {}
              : { title: conversation.title }),
            ...(conversation.access === undefined
              ? {}
              : { access: conversation.access }),
            ...(conversation.subject === undefined
              ? {}
              : {
                  subjectType: conversation.subject.type,
                  subjectId: conversation.subject.id,
                }),
          },
          members: [...(conversation.memberIds ?? [])],
        },
        conversationOf,
      ),
    );

  const targetArgs = (target: SummaryTarget) =>
    "threadId" in target
      ? { conversation: null, thread: target.threadId }
      : { conversation: target.conversationId, thread: null };

  const currentSummary = (target: SummaryTarget) =>
    call("thread_summary", targetArgs(target), (value) =>
      value === null || value === undefined
        ? undefined
        : threadSummaryOf(value),
    );

  /** A thread's root and its newest replies, oldest first. */
  const readThread = (
    threadId: string,
    max: number,
    replies: readonly Message<F>[] = [],
    after?: MessageCursor,
  ): AsyncResult<readonly Message<F>[]> =>
    many("list_replies", {
      message: threadId,
      ...cursorArgs("after", after),
      max_rows: 500,
    }).andThen((page) => {
      const all = [...replies, ...page];
      const last = page.at(-1);

      if (page.length === 500 && last?.sentAt !== undefined) {
        return readThread(threadId, max, all, {
          sentAt: last.sentAt,
          id: last.id,
        });
      }

      return one("get_message", { message: threadId }).map((root) => [
        root,
        ...all.slice(-(max - 1)),
      ]);
    });

  const steps: SummarySteps = {
    current: currentSummary,
    read: (target, max) =>
      "threadId" in target
        ? readThread(target.threadId, max)
        : many("list_messages", {
            conversation: target.conversationId,
            ...cursorArgs("after", undefined),
            ...cursorArgs("before", undefined),
            max_rows: max,
          }).map((messages) =>
            messages.filter((message) => message.threadId === undefined),
          ),
    save: (target, saved) =>
      service(
        "save_thread_summary",
        {
          ...targetArgs(target),
          summary: saved.summary,
          attrs: {
            messageCount: saved.messageCount,
            throughAt: saved.throughAt.toString(),
            ...(saved.model === undefined ? {} : { model: saved.model }),
          },
        },
        threadSummaryOf,
      ),
  };

  const client: Messaging<F> = {
    open,
    openDirect: (userIds) =>
      open({
        kind: new Set(userIds).size > 1 ? "group_dm" : "dm",
        memberIds: userIds,
      }),
    openSubject: (subject) => open({ kind: "subject", subject }),
    addMembers: (conversationId, userIds) =>
      call(
        "add_conversation_members",
        { conversation: conversationId, users: [...userIds] },
        num,
      ),
    removeMember: (conversationId, userId) =>
      call(
        "remove_conversation_member",
        { conversation: conversationId, member: userId },
        (value) => value === true,
      ),
    archive: (conversationId, archived = true) =>
      call(
        "archive_conversation",
        { conversation: conversationId, archived },
        (value) => value === true,
      ),
    conversations: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_conversations",
          {
            tenant: organizationId,
            kinds: list.kinds === undefined ? null : [...list.kinds],
            max_rows: list.limit ?? null,
          },
          (value) => recordsOf(value, "list_conversations").map(summaryOf),
        ),
      ),
    unreadCounts: () =>
      tenant().andThen((organizationId) =>
        call("unread_counts", { tenant: organizationId }, (value) =>
          Object.fromEntries(
            Object.entries(recordOf(value, "unread_counts")).map(
              ([id, count]) => {
                const row = recordOf(count, "unread count");

                return [
                  id,
                  {
                    unread: num(row["unread"]),
                    mentions: num(row["mentions"]),
                  },
                ];
              },
            ),
          ),
        ),
      ),
    markRead: (conversationId, read = {}) =>
      call(
        "mark_read",
        {
          conversation: conversationId,
          thread: read.threadId ?? null,
          read_at: instantArg(read.readAt) ?? null,
        },
        (value) => requiredInstant(value, "readAt"),
      ),
    setNotify: (conversationId, level) =>
      call(
        "set_conversation_notify",
        { conversation: conversationId, level },
        (value) => value === true,
      ),
    typing: (conversationId, typing = true) =>
      call(
        "set_typing",
        { conversation: conversationId, typing },
        (value) => value === true,
      ),
    follow: (target, following = true) =>
      call(
        "follow",
        "conversationId" in target
          ? {
              target_type: "conversation",
              target_id: target.conversationId,
              following,
            }
          : { target_type: "thread", target_id: target.threadId, following },
        (value) => value === true,
      ),
    can: (conversationId, action) =>
      call(
        "can_conversation",
        { conversation: conversationId, action },
        (value) => value === true,
      ),
    send: (conversationId, message) =>
      fields
        .args(message.fields)
        .andThen((checked) =>
          one("send_message", {
            conversation: conversationId,
            body: message.body,
            attrs: {
              ...(message.parentId === undefined
                ? {}
                : { parentId: message.parentId }),
              ...(message.document === undefined
                ? {}
                : { document: message.document }),
              ...(message.anchor === undefined
                ? {}
                : { anchor: message.anchor }),
              ...(message.mentionIds === undefined
                ? {}
                : { mentions: [...message.mentionIds] }),
              ...(message.broadcast === undefined
                ? {}
                : { broadcast: message.broadcast }),
              ...(message.scheduledFor === undefined
                ? {}
                : { scheduledFor: message.scheduledFor.toString() }),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            attachments: [...(message.attachmentIds ?? [])],
          }),
        ),
    edit: (messageId, edition) =>
      fields
        .args(edition.fields)
        .andThen((checked) =>
          one("edit_message", {
            message: messageId,
            body: edition.body,
            attrs: {
              ...(edition.document === undefined
                ? {}
                : { document: edition.document }),
              ...(edition.mentionIds === undefined
                ? {}
                : { mentions: [...edition.mentionIds] }),
              ...(checked === undefined ? {} : { fields: checked }),
            },
          }),
        ),
    remove: (messageId) =>
      call("delete_message", { message: messageId }, (value) => value === true),
    pin: (messageId, pinned = true) =>
      one("pin_message", { message: messageId, pinned }),
    resolve: (messageId, resolved = true) =>
      one("resolve_message", { message: messageId, resolved }),
    list: (conversationId, list = {}) =>
      many("list_messages", {
        conversation: conversationId,
        ...cursorArgs("after", list.after),
        ...cursorArgs("before", list.before),
        max_rows: list.limit ?? null,
      }),
    replies: (messageId, list = {}) =>
      many("list_replies", {
        message: messageId,
        ...cursorArgs("after", list.after),
        max_rows: list.limit ?? null,
      }),
    get: (messageId) =>
      call("get_message", { message: messageId }, (value) =>
        value === null || value === undefined ? undefined : messageOf(value),
      ).andThen((message) =>
        message === undefined
          ? fields.rows([]).map(() => undefined)
          : fields.row(message),
      ),
    edits: (messageId) =>
      call("list_message_edits", { message: messageId }, (value) =>
        recordsOf(value, "list_message_edits").map(editOf),
      ),
    pinned: (conversationId) =>
      many("list_pinned_messages", { conversation: conversationId }),
    recordMentions: (subject, list = {}) =>
      call(
        "list_record_mentions",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          ...cursorArgs("before", list.before),
          max_rows: list.limit ?? null,
        },
        (value) => recordsOf(value, "list_record_mentions").map(mentionOf),
      ).andThen((found) =>
        fields.rows(found.map((item) => item.message)).map((messages) =>
          found.map((item, index) => ({
            conversation: item.conversation,
            // SAFETY: fields.rows returns one row per message, in order.
            message: messages[index] as Message<F>,
          })),
        ),
      ),
    publishDue: (limit) =>
      call("publish_due_messages", { max_rows: limit ?? null }, num),
    summary: currentSummary,
    summarize: (target, summarizer, summarizeOptions) =>
      summarize(steps, target, summarizer, summarizeOptions),
  };

  return withBlockHooks(client, options.hooks, {
    block: "messaging",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
