import type { MessagingEvents } from "../../blocks/messaging/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlAccessProvider } from "../module-types.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./permissions-model.ts";

const CONVERSATION = [
  "organizationId",
  "conversationId",
  "kind",
  "subjectType",
  "subjectId",
] as const;

const MESSAGE = [
  "organizationId",
  "conversationId",
  "messageId",
  "authorId",
  "threadId",
  "subjectType",
  "subjectId",
  "conversationKind",
  "recordType",
  "recordId",
] as const;

const EVENTS: BlockSqlEvents<MessagingEvents> = {
  "conversation.created": {
    subject: "conversations",
    payload: [...CONVERSATION, "recordType", "recordId"],
  },
  "conversation.archived": {
    subject: "conversations",
    payload: [...CONVERSATION],
  },
  "conversation.member_added": {
    subject: "conversations",
    payload: [...CONVERSATION, "userId"],
  },
  "conversation.member_removed": {
    subject: "conversations",
    payload: [...CONVERSATION, "userId"],
  },
  "message.sent": {
    subject: "messages",
    payload: [...MESSAGE, "mentionIds", "recordMentions"],
  },
  "message.edited": { subject: "messages", payload: [...MESSAGE] },
  "message.deleted": { subject: "messages", payload: [...MESSAGE] },
  "message.pinned": { subject: "messages", payload: [...MESSAGE, "pinned"] },
  "message.resolved": {
    subject: "messages",
    payload: [...MESSAGE, "resolved"],
  },
};

export const MESSAGING_NAMES: BlockSqlNames = {
  events: EVENTS,
  entities: {
    message: {
      table: "messages",
      singular: "message",
      primary: true,
      subject: {
        title: "body",
        deletedAt: "deletedAt",
        permissions: { read: "read", write: "send", upload: "send" },
        search: { title: "body", body: [] },
      },
    },
    conversation: {
      table: "conversations",
      singular: "conversation",
      subject: {
        title: "title",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "send", upload: "send" },
      },
    },
  },
  hooks: [
    "before_message_send",
    "after_message_send",
    "before_message_edit",
    "after_message_edit",
  ],
  options: [
    "topic",
    "threadDepth",
    "maxBodyLength",
    "editWindow",
    "scheduleQueue",
    "extraColumns",
    "notify",
  ],
  tables: {
    conversations: {
      name: "conversations",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        access: "access",
        subjectType: "subject_type",
        subjectId: "subject_id",
        title: "title",
        memberKey: "member_key",
        createdBy: "created_by",
        lastMessageAt: "last_message_at",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      typed: ["kind", "access"],
    },
    members: {
      name: "conversation_members",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        conversation: "conversation_id",
        tenant: "tenant_id",
        user: "user_id",
        role: "role",
        notify: "notify",
        lastReadAt: "last_read_at",
        joinedAt: "joined_at",
      },
      optional: ["notify", "joinedAt"],
      typed: ["role", "notify"],
    },
    messages: {
      name: "messages",
      app: {},
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        parent: "parent_id",
        thread: "thread_id",
        author: "author_id",
        kind: "kind",
        body: "body",
        document: "document",
        anchor: "anchor",
        mentions: "mentions",
        mentionScope: "mention_scope",
        broadcast: "broadcast",
        replyCount: "reply_count",
        lastReplyAt: "last_reply_at",
        replyUsers: "reply_user_ids",
        pinnedAt: "pinned_at",
        pinnedBy: "pinned_by",
        resolvedAt: "resolved_at",
        resolvedBy: "resolved_by",
        scheduledFor: "scheduled_for",
        sentAt: "sent_at",
        editedAt: "edited_at",
        deletedAt: "deleted_at",
        createdAt: "created_at",
      },
      optional: ["anchor", "scheduledFor", "resolvedAt", "resolvedBy"],
      typed: ["kind", "mentionScope"],
    },
    edits: {
      name: "message_edits",
      app: {},
      optional: ["document", "editor"],
      lifecycle: { tenant: "tenant", user: "editor", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        message: "message_id",
        body: "body",
        document: "document",
        editor: "edited_by",
        editedAt: "edited_at",
      },
    },
    reads: {
      name: "thread_reads",
      app: {},
      lifecycle: { tenant: "tenant", user: "user" },
      columns: {
        tenant: "tenant_id",
        user: "user_id",
        conversation: "conversation_id",
        thread: "thread_id",
        lastReadAt: "last_read_at",
      },
    },
    recordMentions: {
      name: "message_record_mentions",
      app: {},
      lifecycle: { tenant: "tenant" },
      columns: {
        tenant: "tenant_id",
        message: "message_id",
        conversation: "conversation_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        createdAt: "created_at",
      },
    },
    summaries: {
      name: "thread_summaries",
      app: {},
      optional: ["model", "createdAt", "updatedAt"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        thread: "thread_id",
        summary: "summary",
        model: "model",
        messageCount: "message_count",
        throughAt: "through_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

type Action = keyof BlockSqlOperations<"messaging">;

const NAME = /^[a-z][a-z0-9_-]{0,30}$/;
const QUEUE = /^[a-z][a-z0-9_]{0,40}$/;

/** The table, column and permission helpers the messaging SQL shares. */
export interface MessagingSql {
  readonly ctx: BlockSqlContext;
  readonly id: string;
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  /** A column accessor for one table. */
  readonly cols: (table: string) => (column: string) => string;
  /** The permission key literal of an action. */
  readonly key: (action: Action) => string;
  /** `can()` for the caller on a tenant expression. */
  readonly can: (tenant: string, action: Action) => string;
  /**
   * Whether the caller holds the action's key on the record itself, through
   * `config.subjects.<type>.scope`; `undefined` when no subject sets a scope.
   */
  readonly onRecord: (
    type: string,
    id: string,
    action: Action,
  ) => string | undefined;
  /** An entity name, event type or payload key after the entity renames. */
  readonly e: (name: string) => string;
  readonly service: string;
  readonly topic: string;
  /** 1 for replies to roots only, 0 for unlimited depth. */
  readonly threadDepth: number;
  readonly maxBody: number;
  /** Seconds an author may edit a message; 0 for always. */
  readonly editWindow: number;
  readonly scheduleQueue: string;
}

export function messagingSql(
  ctx: BlockSqlContext,
  provider?: BlockSqlAccessProvider,
): MessagingSql {
  const permissions = moduleOperations("messaging");

  const key = (action: Action): string =>
    ctx.permission(action, permissions[action]);

  const topic = ctx.text("topic", "messages");

  if (!NAME.test(topic)) {
    throw new TypeError(
      "blocks.messaging.options.topic must be a lowercase name of at most 31 characters",
    );
  }

  const depth = ctx.option("threadDepth");

  if (depth !== undefined && depth !== 1 && depth !== "unlimited") {
    throw new TypeError(
      'blocks.messaging.options.threadDepth must be 1 or "unlimited"',
    );
  }

  const maxBody = ctx.number("maxBodyLength", 40_000);

  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "blocks.messaging.options.maxBodyLength must be a whole number above zero",
    );
  }

  const editWindow = ctx.number("editWindow", 0);

  if (!Number.isInteger(editWindow) || editWindow < 0) {
    throw new TypeError(
      "blocks.messaging.options.editWindow must be 0 (always) or a number of seconds",
    );
  }

  const scheduleQueue = ctx.text("scheduleQueue", "messaging");

  if (!QUEUE.test(scheduleQueue)) {
    throw new TypeError(
      "blocks.messaging.options.scheduleQueue must be a lowercase queue name",
    );
  }

  const scoped = registeredSubjects(ctx.subjects, ctx.naming).flatMap(
    (subject) =>
      subject.config.scope === undefined
        ? []
        : [{ type: subject.type, scope: subject.config.scope }],
  );

  // A provider answers scope grants through its idsWith set; the access
  // module through can() on the scope.
  const onRecord = (
    type: string,
    id: string,
    action: Action,
  ): string | undefined =>
    scoped.length === 0
      ? undefined
      : `coalesce(case ${type} ${scoped
          .map(
            ({ type: name, scope }) =>
              `when ${sqlString(name)} then ${
                provider === undefined
                  ? ctx.can(scope, id, key(action))
                  : `${id} in (select t.id::text from ${fillTemplate(`subjects.${name}.scope`, provider.functions.idsWith, { permission: key(action), scope })} as t(id))`
              }`,
          )
          .join(" ")} else false end, false)`;

  return {
    ctx,
    id: ctx.idType,
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    cols: (table) => (column) => ctx.col(table, column),
    key,
    can: (tenant, action) => ctx.scope.can(tenant, key(action)),
    onRecord,
    e: (name) => ctx.resolved.entityNaming.rename(name),
    service: SERVICE_CALLER,
    topic,
    threadDepth: depth === "unlimited" ? 0 : 1,
    maxBody,
    editWindow,
    scheduleQueue,
  };
}

/** `'<prefix>' || <expr>`: the private Realtime topic of a conversation. */
export const conversationTopic = (q: MessagingSql, id: string): string =>
  `${sqlString(`${q.topic}:`)} || ${id}::text`;

/**
 * Row `row` of `table` as `to_jsonb` gives it on the module's own table: keyed
 * by the default column names, with null for a column the app's table lacks and
 * none of the app's other columns.
 */
export function messagingRowJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
): string {
  if (ctx.owns(table)) {
    return `to_jsonb(${row})`;
  }

  const columns = MESSAGING_NAMES.tables[table]?.columns ?? {};

  return `jsonb_build_object(${Object.entries(columns)
    .map(
      ([logical, name]) =>
        `${sqlString(name)}, ${ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null"}`,
    )
    .join(", ")})`;
}
