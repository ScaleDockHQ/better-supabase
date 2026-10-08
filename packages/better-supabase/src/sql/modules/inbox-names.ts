import type { ModuleContext, ModuleNames } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

export const INBOX_NAMES: ModuleNames = {
  options: [
    "topic",
    "bucket",
    "maxBodyLength",
    "botQueue",
    "outboundQueue",
    "notify",
  ],
  tables: {
    inboxes: {
      name: "inboxes",
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
      columns: {
        inbox: "inbox_id",
        user: "user_id",
        role: "role",
        createdAt: "created_at",
      },
    },
    teams: {
      name: "inbox_teams",
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        createdAt: "created_at",
      },
    },
    teamMembers: {
      name: "inbox_team_members",
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
      name: "conversations",
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
    participants: {
      name: "conversation_participants",
      columns: {
        conversation: "conversation_id",
        user: "user_id",
        role: "role",
        createdAt: "created_at",
      },
    },
    events: {
      name: "conversation_events",
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
    reads: {
      name: "conversation_reads",
      columns: {
        conversation: "conversation_id",
        user: "user_id",
        lastReadAt: "last_read_at",
      },
    },
    messages: {
      name: "inbox_messages",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        conversation: "conversation_id",
        direction: "direction",
        kind: "kind",
        authorType: "author_type",
        author: "author_id",
        body: "body",
        format: "format",
        attachments: "attachments",
        reactions: "reactions",
        mentions: "mentions",
        externalId: "external_id",
        replyTo: "reply_to",
        metadata: "metadata",
        createdAt: "created_at",
        editedAt: "edited_at",
        deletedAt: "deleted_at",
      },
    },
    deliveries: {
      name: "message_deliveries",
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
    mentions: {
      name: "inbox_mentions",
      columns: {
        message: "message_id",
        user: "user_id",
        tenant: "tenant_id",
        createdAt: "created_at",
      },
    },
    inbound: {
      name: "inbound_events",
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
  },
};

type Action = keyof typeof MODULE_PERMISSIONS.inbox;

const NAME = /^[a-z][a-z0-9_-]{0,30}$/;
const QUEUE = /^[a-z][a-z0-9_]{0,40}$/;

/** The table, column and permission helpers the inbox SQL shares. */
export interface InboxSql {
  readonly ctx: ModuleContext;
  readonly id: string;
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  /** A column accessor for one table. */
  readonly cols: (table: string) => (column: string) => string;
  /** The permission key literal of an action. */
  readonly key: (action: Action) => string;
  /** `can()` for the caller on a tenant expression. */
  readonly can: (tenant: string, action: Action) => string;
  /** The policy form: the tenant is one the caller holds the key in. */
  readonly staff: (tenant: string, action?: Action) => string;
  readonly service: string;
  readonly topic: string;
  readonly bucket: string;
  readonly maxBody: number;
  readonly botQueue: string;
  readonly outboundQueue: string;
}

export function inboxSql(ctx: ModuleContext): InboxSql {
  const permissions = MODULE_PERMISSIONS.inbox;
  const key = (action: Action): string =>
    ctx.permission(action, permissions[action]);
  const topic = ctx.text("topic", "inbox");
  if (!NAME.test(topic)) {
    throw new TypeError(
      "sql.modules.inbox.options.topic must be a lowercase name of at most 31 characters",
    );
  }
  const bucket = ctx.text("bucket", "inbox-files");
  if (!/^[a-z0-9][a-z0-9_-]{0,62}$/.test(bucket)) {
    throw new TypeError(
      "sql.modules.inbox.options.bucket must be a lowercase bucket id",
    );
  }
  const maxBody = ctx.number("maxBodyLength", 20_000);
  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "sql.modules.inbox.options.maxBodyLength must be a whole number above zero",
    );
  }
  const queue = (name: string, fallback: string): string => {
    const value = ctx.text(name, fallback);
    if (!QUEUE.test(value)) {
      throw new TypeError(
        `sql.modules.inbox.options.${name} must be a lowercase queue name`,
      );
    }
    return value;
  };
  return {
    ctx,
    id: ctx.idType,
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    cols: (table) => (column) => ctx.col(table, column),
    key,
    can: (tenant, action) =>
      `coalesce(better_supabase.can('tenant', ${tenant}, ${key(action)}), false)`,
    staff: (tenant, action = "read") => tenantIn(tenant, key(action)),
    service: SERVICE_CALLER,
    topic,
    bucket,
    maxBody,
    botQueue: queue("botQueue", "inbox_bot"),
    outboundQueue: queue("outboundQueue", "inbox_outbound"),
  };
}

/** `'<topic>:' || expr` and `'<topic>:org:' || expr` as SQL. */
export function topics(q: InboxSql): {
  readonly conversation: (id: string) => string;
  readonly org: (tenant: string) => string;
} {
  return {
    conversation: (id) => `${sqlString(`${q.topic}:`)} || ${id}::text`,
    org: (tenant) => `${sqlString(`${q.topic}:org:`)} || ${tenant}::text`,
  };
}
