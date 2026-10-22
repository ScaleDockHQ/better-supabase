import type { ModuleContext, ModuleContractFunction } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../module-types.ts";

import { schemaPreamble } from "../shared.ts";
import { messagingFunctions } from "./messaging-functions.ts";
import { messagingInbox } from "./messaging-inbox.ts";
import { MESSAGING_NAMES, messagingSql } from "./messaging-names.ts";
import { messagingRealtime, messagingTables } from "./messaging-tables.ts";

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const q = messagingSql(ctx, layout.accessProvider);

  return `${schemaPreamble(ctx)}
-- Messaging: conversations (channels, direct and group messages, one per
-- record, the inbox's) with members, messages with threads, mentions, edits,
-- pins and resolution, scheduled sends and read markers. Writes go through
-- the functions; Realtime pings carry ids only.
${messagingTables(q)}

${messagingFunctions(q)}

${messagingRealtime(q)}${
    ctx.installed("inbox")
      ? `

${messagingInbox(q)}`
      : ""
  }`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const functions: ModuleContractFunction[] = [
    { name: "can_conversation", args: ["uuid", "text"], returns: "boolean" },
    {
      name: "open_conversation",
      args: ["{id}", "text", "jsonb", "uuid[]"],
      returns: "jsonb",
    },
    {
      name: "add_conversation_members",
      args: ["uuid", "uuid[]"],
      returns: "integer",
    },
    {
      name: "remove_conversation_member",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    {
      name: "archive_conversation",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    {
      name: "list_conversations",
      args: ["{id}", "text[]", "integer"],
      returns: "jsonb",
    },
    { name: "unread_counts", args: ["{id}"], returns: "jsonb" },
    {
      name: "mark_read",
      args: ["uuid", "uuid", "timestamptz"],
      returns: "timestamptz",
    },
    {
      name: "conversation_read_at",
      args: ["uuid", "uuid"],
      returns: "timestamptz",
    },
    {
      name: "set_conversation_notify",
      args: ["uuid", "text"],
      returns: "boolean",
    },
    {
      name: "set_typing",
      args: ["uuid", "boolean", "text"],
      returns: "boolean",
    },
    {
      name: "send_message",
      args: ["uuid", "text", "jsonb", "uuid[]"],
      returns: "jsonb",
    },
    { name: "publish_due_messages", args: ["integer"], returns: "integer" },
    { name: "edit_message", args: ["uuid", "text", "jsonb"], returns: "jsonb" },
    { name: "delete_message", args: ["uuid"], returns: "boolean" },
    { name: "pin_message", args: ["uuid", "boolean"], returns: "jsonb" },
    { name: "resolve_message", args: ["uuid", "boolean"], returns: "jsonb" },
    {
      name: "list_messages",
      args: ["uuid", "timestamptz", "uuid", "timestamptz", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "list_replies",
      args: ["uuid", "timestamptz", "uuid", "integer"],
      returns: "jsonb",
    },
    { name: "get_message", args: ["uuid"], returns: "jsonb" },
    { name: "list_message_edits", args: ["uuid"], returns: "jsonb" },
    { name: "list_pinned_messages", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_record_mentions",
      args: ["text", "text", "timestamptz", "uuid", "integer"],
      returns: "jsonb",
    },
  ];

  if (ctx.installed("notifications")) {
    const n = ctx.of("notifications");

    if (n.hasTable("subscriptions")) {
      functions.push({
        name: "follow",
        args: ["text", "uuid", "boolean"],
        returns: "boolean",
      });
    }
  }

  return functions;
}

export const MESSAGING: ModuleDefinition = {
  internal: [
    "is_conversation_member",
    "conversation_topic_allowed",
    "messaging_messages_json",
    "message_authors",
    "parse_mentions",
    "index_record_mentions",
  ],
  // delete_message empties a message and stamps deleted_at; nothing clears it.
  hidingColumns: ["messages.deletedAt"],
  name: "messaging",
  scopes: ["tenant"],
  title: "Messaging",
  description:
    "Conversations and messages shared by channels, record discussions and the inbox: channels, direct and group messages, one conversation per record, members with read markers and notification levels, threads, mentions, edits with history, pins, resolved threads, scheduled sends, files and reactions. Members, the tenant or the record's readers read a conversation; Realtime pings carry ids only.",
  requires: ["tenant", "access", "subjects"],
  integrates: [
    "notifications",
    "jobs",
    "profiles",
    "attachments",
    "reactions",
    "data-lifecycle",
    "inbox",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: MESSAGING_NAMES,
  contract,
  build,
  topics: (ctx) => [`${messagingSql(ctx).topic}:{conversationId}`],
};
