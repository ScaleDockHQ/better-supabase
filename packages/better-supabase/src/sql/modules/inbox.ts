import type { ModuleContext, ModuleContractFunction } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";
import { inboxFunctions } from "./inbox-functions.ts";
import { INBOX_NAMES, inboxSql } from "./inbox-names.ts";
import { inboxServiceFunctions } from "./inbox-service.ts";
import {
  inboxHelpers,
  inboxRealtime,
  inboxStorage,
  inboxTables,
} from "./inbox-tables.ts";

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const q = inboxSql(ctx);
  return `${schemaPreamble(ctx)}
-- A shared inbox: conversations with contacts across the in-app widget and
-- the channels better-supabase/chat-sdk connects, internal notes, mentions,
-- assignment to members and teams, bot hand-off and delivery status. Staff
-- read through the inbox.read key; a signed-in contact reads their own
-- conversations without the notes. Writes go through the functions.
${inboxTables(q)}

${inboxHelpers(q)}

${inboxFunctions(q)}

${inboxServiceFunctions(q)}

${inboxRealtime(q)}

${inboxStorage(q)}`;
}

// An existing bucket keeps its settings.
function data(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const { bucket } = inboxSql(ctx);
  return `insert into storage.buckets (id, name, public, file_size_limit)
values (${sqlString(bucket)}, ${sqlString(bucket)}, false, 26214400)
on conflict (id) do nothing;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_inbox",
      args: ["{id}", "text", "text", "jsonb", "text", "text"],
      returns: "jsonb",
    },
    { name: "update_inbox", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "set_inbox_member",
      args: ["uuid", "uuid", "text"],
      returns: "boolean",
    },
    { name: "create_inbox_team", args: ["{id}", "text"], returns: "jsonb" },
    {
      name: "set_inbox_team_member",
      args: ["uuid", "uuid", "boolean"],
      returns: "boolean",
    },
    { name: "upsert_contact", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "start_conversation", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "send_message", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "record_inbound", args: ["jsonb"], returns: "jsonb" },
    {
      name: "assign_conversation",
      args: ["uuid", "uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "set_conversation_status",
      args: ["uuid", "text", "timestamptz"],
      returns: "jsonb",
    },
    { name: "set_bot_mode", args: ["uuid", "text", "text"], returns: "jsonb" },
    {
      name: "mark_conversation_read",
      args: ["uuid"],
      returns: "timestamptz",
    },
    {
      name: "react_to_message",
      args: ["uuid", "text", "boolean", "text"],
      returns: "jsonb",
    },
    {
      name: "edit_message",
      args: ["uuid", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "list_conversations", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_conversation", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_messages",
      args: ["uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "list_conversation_events", args: ["uuid"], returns: "jsonb" },
    { name: "inbox_counts", args: ["{id}"], returns: "jsonb" },
    {
      name: "record_delivery",
      args: ["uuid", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "set_delivery_status",
      args: ["text", "text", "text", "text"],
      returns: "integer",
    },
    {
      name: "store_inbound_event",
      args: ["text", "text", "text", "jsonb", "uuid", "{id}"],
      returns: "jsonb",
    },
    {
      name: "set_inbound_event_status",
      args: ["uuid", "text", "text"],
      returns: "boolean",
    },
    {
      name: "pending_inbound_events",
      args: ["integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "purge_inbound_events",
      args: ["interval", "integer"],
      returns: "integer",
    },
    { name: "wake_snoozed_conversations", args: [], returns: "integer" },
    {
      name: "upsert_message_template",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_message_template", args: ["uuid"], returns: "boolean" },
    { name: "purge_contact", args: ["uuid"], returns: "jsonb" },
    { name: "get_message", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_typing",
      args: ["uuid", "boolean", "text"],
      returns: "boolean",
    },
  ];
}

export const INBOX: ModuleDefinition = {
  internal: [
    "inbox_contact_ids",
    "inbox_contact_conversation_ids",
    "inbox_conversation_allowed",
    "inbox_conversation_json",
    "inbox_resolve_contact",
    "inbox_add_message",
    "inbox_file_allowed",
    "inbox_message_broadcast",
    "inbox_conversation_broadcast",
    "inbox_delivery_broadcast",
  ],
  name: "inbox",
  title: "Shared inbox",
  description:
    "Conversations with contacts across the in-app widget and chat channels: inboxes, members and teams, contacts with their channel identities, messages and internal notes, mentions, assignment, bot hand-off, read state, delivery status, stored webhook events and message templates. Staff read with inbox.read; contacts read their own conversations without the notes; Realtime pings carry ids only.",
  requires: ["tenant", "access", "updated-at", "jobs", "streams"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: INBOX_NAMES,
  contract,
  build,
  data,
  topics: (ctx) => {
    const { topic } = inboxSql(ctx);
    return [`${topic}:{conversationId}`, `${topic}:org:{organizationId}`];
  },
};
