import type { InboxEvents } from "../../blocks/inbox/events.ts";
import type { OperationTable } from "../../core/operations.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import {
  OPERATION_PREFIXES,
  operationPermission,
} from "../../core/operations.ts";
import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { messagingSql } from "./messaging-names.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<InboxEvents> = {
  "inbox_conversation.reopened": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "inboxId",
      "contactId",
      "assigneeId",
      "status",
    ],
  },
  "inbox_message.received": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "messageId",
      "inboxId",
      "contactId",
    ],
    retries: true,
  },
  "inbox_conversation.opened": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "inboxId",
      "contactId",
      "assigneeId",
      "status",
    ],
  },
  "inbox_conversation.assigned": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "inboxId",
      "contactId",
      "assigneeId",
      "status",
      "previousAssigneeId",
    ],
  },
  "inbox_conversation.resolved": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "inboxId",
      "contactId",
      "assigneeId",
      "status",
    ],
  },
  "inbox_conversation.unsnoozed": {
    subject: "conversations",
    payload: [
      "conversationId",
      "organizationId",
      "inboxId",
      "contactId",
      "assigneeId",
      "status",
    ],
  },
};

export const INBOX_NAMES: BlockSqlNames = {
  events: EVENTS,
  options: [
    "topic",
    "bucket",
    "maxBodyLength",
    "botQueue",
    "outboundQueue",
    "scheduleQueue",
    "notify",
  ],
  tables: {
    inboxes: {
      name: "inboxes",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        channel: "channel",
        address: "channel_address",
        installation: "installation_id",
        botMode: "bot_mode",
        settings: "settings",
        createdAt: "created_at",
        updatedAt: "updated_at",
        archivedAt: "archived_at",
      },
    },
    members: {
      name: "inbox_members",
      lifecycle: { user: "user" },
      columns: {
        inbox: "inbox_id",
        user: "user_id",
        role: "role",
        createdAt: "created_at",
      },
    },
    teams: {
      name: "inbox_teams",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        createdAt: "created_at",
      },
    },
    teamMembers: {
      name: "inbox_team_members",
      lifecycle: { user: "user" },
      columns: { team: "team_id", user: "user_id", createdAt: "created_at" },
    },
    contacts: {
      name: "contacts",
      lifecycle: { tenant: "tenant", user: "user" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        name: "name",
        email: "email",
        phone: "phone",
        avatarUrl: "avatar_url",
        metadata: "metadata",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    identities: {
      name: "contact_identities",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        contact: "contact_id",
        channel: "channel",
        externalId: "external_id",
        createdAt: "created_at",
      },
    },
    conversations: {
      name: "inbox_conversations",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        inbox: "inbox_id",
        contact: "contact_id",
        subject: "subject",
        status: "status",
        priority: "priority",
        assignee: "assignee_id",
        team: "team_id",
        botMode: "bot_mode",
        thread: "thread_id",
        snoozedUntil: "snoozed_until",
        lastMessageAt: "last_message_at",
        preview: "last_message_preview",
        firstResponseAt: "first_response_at",
        resolvedAt: "resolved_at",
        metadata: "metadata",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    events: {
      name: "conversation_events",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        type: "type",
        actor: "actor_id",
        data: "data",
        createdAt: "created_at",
      },
    },
    details: {
      name: "inbox_message_details",
      lifecycle: { tenant: "tenant" },
      columns: {
        message: "message_id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        direction: "direction",
        authorType: "author_type",
        format: "format",
        externalId: "external_id",
        replyTo: "reply_to",
        metadata: "metadata",
      },
    },
    deliveries: {
      name: "message_deliveries",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        message: "message_id",
        channel: "channel",
        status: "status",
        externalId: "external_id",
        error: "error",
        attempts: "attempts",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    inbound: {
      name: "inbound_events",
      lifecycle: { tenant: "tenant", omit: ["headers"] },
      columns: {
        id: "id",
        tenant: "tenant_id",
        adapter: "adapter",
        externalId: "external_id",
        inbox: "inbox_id",
        headers: "headers",
        body: "body",
        status: "status",
        error: "error",
        attempts: "attempts",
        receivedAt: "received_at",
        processedAt: "processed_at",
      },
    },
    templates: {
      name: "message_templates",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        inbox: "inbox_id",
        name: "name",
        channel: "channel",
        language: "language",
        body: "body",
        variables: "variables",
        externalId: "external_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scheduled: {
      name: "scheduled_inbox_messages",
      lifecycle: { tenant: "tenant", user: "author" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        author: "author_id",
        input: "input",
        scheduledFor: "scheduled_for",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
  migrations: [
    {
      from: 2,
      description:
        "The conversations table is inbox_conversations, so the messaging block owns conversations.",
      table: "conversations",
      was: "conversations",
    },
  ],
};

type Action = keyof BlockSqlOperations<"inbox">;

const NAME = /^[a-z][a-z0-9_-]{0,30}$/;
const QUEUE = /^[a-z][a-z0-9_]{0,40}$/;

/** The table, column and permission helpers the inbox SQL shares. */
export interface InboxSql {
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
   * `can()` for a staff command on a conversation: the provider's
   * `inbox.command.<name>` operation, else the key of `action`.
   */
  readonly command: (
    tenant: string,
    name: InboxCommand,
    action: Action,
  ) => string;
  /** The policy form: the tenant is one the caller holds the key in. */
  readonly staff: (tenant: string, action?: Action) => string;
  readonly service: string;
  readonly topic: string;
  readonly bucket: string;
  readonly maxBody: number;
  readonly botQueue: string;
  readonly outboundQueue: string;
  readonly scheduleQueue: string;
  /** The messaging core, which holds the conversations and messages. */
  readonly core: {
    readonly ctx: BlockSqlContext;
    readonly t: (table: string) => string;
    readonly cols: (table: string) => (column: string) => string;
    readonly fn: (name: string) => string;
    /** `'<messaging topic>:' || id` as SQL. */
    readonly topic: (id: string) => string;
    /** The subject type literal of a core message. */
    readonly message: string;
    /** The subject type literal of a core conversation. */
    readonly conversation: string;
  };
}

/** The staff commands whose permission `inbox.command.<name>` can name. */
export type InboxCommand = "assign" | "set_status" | "set_bot_mode" | "reply";

export function inboxSql(
  ctx: BlockSqlContext,
  operations?: OperationTable,
): InboxSql {
  const permissions = moduleOperations("inbox");

  const key = (action: Action): string =>
    ctx.permission(action, permissions[action]);

  const commandKey = (name: InboxCommand, action: Action): string => {
    const fallback = ctx.permissionKey(action, permissions[action]);

    return sqlString(
      operationPermission(
        operations,
        `${OPERATION_PREFIXES.inboxCommand}${name}`,
        fallback,
      ) ?? fallback,
    );
  };

  const topic = ctx.text("topic", "inbox");

  if (!NAME.test(topic)) {
    throw new TypeError(
      "blocks.inbox.options.topic must be a lowercase name of at most 31 characters",
    );
  }

  const bucket = ctx.text("bucket", "inbox-files");

  if (!/^[a-z0-9][a-z0-9_-]{0,62}$/.test(bucket)) {
    throw new TypeError(
      "blocks.inbox.options.bucket must be a lowercase bucket id",
    );
  }

  const maxBody = ctx.number("maxBodyLength", 20_000);

  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "blocks.inbox.options.maxBodyLength must be a whole number above zero",
    );
  }

  const queue = (name: string, fallback: string): string => {
    const value = ctx.text(name, fallback);

    if (!QUEUE.test(value)) {
      throw new TypeError(
        `blocks.inbox.options.${name} must be a lowercase queue name`,
      );
    }

    return value;
  };

  const core = ctx.of("messaging");
  const m = messagingSql(core);

  return {
    core: {
      ctx: core,
      t: (table) => core.table(table),
      cols: (table) => (column) => core.col(table, column),
      fn: (name) => core.fn(name),
      topic: (id) => `${sqlString(`${m.topic}:`)} || ${id}::text`,
      message: sqlString(m.e("message")),
      conversation: sqlString(m.e("conversation")),
    },
    ctx,
    id: ctx.idType,
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    cols: (table) => (column) => ctx.col(table, column),
    key,
    can: (tenant, action) => ctx.can("tenant", tenant, key(action)),
    command: (tenant, name, action) =>
      ctx.can("tenant", tenant, commandKey(name, action)),
    staff: (tenant, action = "read") => ctx.scope.check(tenant, key(action)),
    service: SERVICE_CALLER,
    topic,
    bucket,
    maxBody,
    botQueue: queue("botQueue", "inbox_bot"),
    outboundQueue: queue("outboundQueue", "inbox_outbound"),
    scheduleQueue: queue("scheduleQueue", "inbox_schedule"),
  };
}

/** `'<topic>:org:' || expr` as SQL. */
export function topics(q: InboxSql): {
  readonly org: (tenant: string) => string;
} {
  return {
    org: (tenant) => `${sqlString(`${q.topic}:org:`)} || ${tenant}::text`,
  };
}

export const forbidden = (what: string): string =>
  fail("INBOX_FORBIDDEN", what);

export const missing = (what: string, hint: string): string =>
  fail(hint, `${what} not found`, "P0002");
