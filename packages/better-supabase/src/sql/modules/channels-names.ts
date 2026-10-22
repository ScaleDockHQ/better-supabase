import type { ChannelsEvents } from "../../blocks/channels/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { MessagingSql } from "./messaging-names.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { messagingSql } from "./messaging-names.ts";
import { moduleOperations } from "./permissions-model.ts";

const CHANNEL = [
  "organizationId",
  "channelId",
  "name",
  "visibility",
  "recordType",
  "recordId",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<ChannelsEvents> = {
  "channel.created": { subject: "channels", payload: [...CHANNEL] },
  "channel.updated": { subject: "channels", payload: [...CHANNEL] },
};

export const CHANNELS_NAMES: BlockSqlNames = {
  events: EVENTS,
  entities: {
    channel: {
      table: "channels",
      singular: "channel",
      primary: true,
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
        search: { title: "name", body: ["topic", "purpose"] },
      },
    },
  },
  tables: {
    channels: {
      name: "channels",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        visibility: "visibility",
        topic: "topic",
        purpose: "purpose",
        subjectType: "subject_type",
        subjectId: "subject_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

type Action = keyof BlockSqlOperations<"channels">;

/** The helpers the channels SQL shares, over the messaging ones. */
export interface ChannelsSql {
  readonly ctx: BlockSqlContext;
  readonly m: MessagingSql;
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly ch: (column: string) => string;
  /** A conversations column, through the messaging module. */
  readonly cv: (column: string) => string;
  readonly mb: (column: string) => string;
  /** `messaging.<name>`. */
  readonly mfn: (name: string) => string;
  readonly conversations: string;
  readonly members: string;
  readonly key: (action: Action) => string;
  readonly can: (tenant: string, action: Action) => string;
  readonly e: (name: string) => string;
}

export function channelsSql(ctx: BlockSqlContext): ChannelsSql {
  const permissions = moduleOperations("channels");
  const messaging = ctx.of("messaging");

  const key = (action: Action): string =>
    ctx.permission(action, permissions[action]);

  return {
    ctx,
    m: messagingSql(messaging),
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    ch: (column) => ctx.col("channels", column),
    cv: (column) => messaging.col("conversations", column),
    mb: (column) => messaging.col("members", column),
    mfn: (name) => messaging.fn(name),
    conversations: messaging.table("conversations"),
    members: messaging.table("members"),
    key,
    can: (tenant, action) => ctx.scope.can(tenant, key(action)),
    e: (name) => ctx.resolved.entityNaming.rename(name),
  };
}
