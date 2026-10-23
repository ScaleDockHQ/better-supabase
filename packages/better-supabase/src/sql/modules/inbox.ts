import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type {
  BlockSqlDefinition,
  BlockSqlLayout,
  BlockSqlUpgrade,
} from "../module-types.ts";

import { CONVERSATION_TO_TASK } from "../../blocks/inbox/automations.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";
import { shippedAutomation } from "./automation-defaults.ts";
import { inboxFunctions } from "./inbox-functions.ts";
import { INBOX_NAMES, inboxSql } from "./inbox-names.ts";
import { inboxScheduleFunctions } from "./inbox-schedule.ts";
import { inboxServiceFunctions } from "./inbox-service.ts";
import {
  inboxDetailsDdl,
  inboxHelpers,
  inboxRealtime,
  inboxStorage,
  inboxTables,
} from "./inbox-tables.ts";
import { messagingSql } from "./messaging-names.ts";
import { messagingTableDdl } from "./messaging-tables.ts";

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const q = inboxSql(ctx, layout.accessProvider?.operations);
  const teams = ctx.installed("teams") ? ctx.of("teams") : undefined;
  const sharedTeams = teams !== undefined;

  return `${schemaPreamble(ctx)}
-- A shared inbox on the messaging core: each conversation with a contact is
-- a core conversation of kind inbox, each message (or internal note) a core
-- message with its inbox fields in inbox_message_details, and files are
-- attachments. Across the in-app widget and the channels
-- better-supabase/chat-sdk connects, with assignment to members and teams,
-- bot hand-off and delivery status. Staff read through the inbox.read key; a
-- signed-in contact reads their own conversations without the notes. Writes
-- go through the functions.
${inboxTables(q, sharedTeams)}

${inboxHelpers(q)}

${inboxFunctions(
  q,
  teams && {
    create: teams.fn("create_team"),
    add: teams.fn("add_team_member"),
    remove: teams.fn("remove_team_member"),
  },
)}

${inboxServiceFunctions(q)}

${inboxScheduleFunctions(q)}

${inboxRealtime(q)}

${inboxStorage(q)}`;
}

// The module file creates the new names; the old ones go, and the moved
// table's primary key takes its new name so messaging can create its own.
function renamedFunctions(ctx: BlockSqlContext): string {
  const { id } = inboxSql(ctx);

  const old = [
    "send_message(uuid, jsonb)",
    "edit_message(uuid, text, boolean)",
    "get_message(uuid)",
    "list_messages(uuid, timestamptz, integer)",
    `list_conversations(${id}, jsonb)`,
    "set_typing(uuid, boolean, text)",
  ];

  const table = ctx.tableName("conversations");

  return `${old.map((signature) => `drop function if exists ${ctx.schema}.${signature};`).join("\n")}
alter index if exists ${ctx.schema}.conversations_pkey rename to ${sqlIdent(`${table.name}_pkey`)};`;
}

const LEGACY_FUNCTIONS = [
  "react_to_message(uuid, text, boolean, text)",
  "set_inbox_typing(uuid, boolean, text)",
  "inbox_file_allowed(text, boolean)",
  "inbox_read_broadcast()",
  "inbox_contact_conversation_ids()",
  "inbox_add_message(uuid, jsonb, text, uuid, text)",
];

// The data moves before the module files run, so the step creates the core
// tables and the details table it copies into; the schema diff adds the rest.
const TO_MESSAGING: BlockSqlUpgrade = {
  from: 3,
  description:
    "The inbox moves onto the messaging core: each conversation becomes a core conversation of kind inbox with the same id, messages and notes become core messages with the same ids and their inbox fields in inbox_message_details, participants and read markers become conversation members, files become pending attachments for pending_inbox_files to import, and reactions move to the message.",
  sql: (ctx) => {
    const q = inboxSql(ctx);
    const core = q.core;
    const m = messagingSql(core.ctx);
    const conv = core.t("conversations");
    const msg = core.t("messages");
    const members = core.t("members");
    const cc = core.cols("conversations");
    const cm = core.cols("messages");
    const ck = core.cols("members");
    const cv = q.cols("conversations");
    const ct = q.cols("contacts");
    const dt = q.cols("details");
    const old = (name: string): string => `${ctx.schema}.${name}`;
    const messages = old("inbox_messages");
    const at = ctx.of("attachments");
    const files = at.table("attachments");
    const a = (column: string): string => at.col("attachments", column);

    const reactions = (() => {
      if (!ctx.installed("reactions")) {
        return `  if exists (select 1 from ${messages} x where x.reactions <> '{}'::jsonb) then
    raise warning 'inbox: reactions on messages are dropped; install the reactions block to keep them';
  end if;`;
      }

      const r = ctx.of("reactions");
      const table = r.table("reactions");
      const c = (column: string): string => r.col("reactions", column);

      return `  update ${table} x set ${c("subjectType")} = ${core.message} where x.${c("subjectType")} = 'inbox_message';
  perform set_config('better_supabase.bsb_reactions_backfill', 'on', true);
  insert into ${table} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("actor")}, ${c("user")}, ${c("emoji")})
  select x.tenant_id, ${core.message}, x.id::text, w.actor,
    case when w.actor ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then w.actor::uuid end,
    e.key
  from ${messages} x
  cross join lateral jsonb_each(x.reactions) e
  cross join lateral jsonb_array_elements_text(e.value) w(actor)
  where jsonb_typeof(e.value) = 'array' and length(e.key) between 1 and 64 and e.key !~ '\\s' and e.key !~ '^:[a-z0-9_+-]{1,32}:$'
  on conflict do nothing;
  perform set_config('better_supabase.bsb_reactions_backfill', '', true);`;
    })();

    return `-- The messaging tables and the inbox details, so the messages can move before the module files run.
${messagingTableDdl(m)}
alter table ${msg} add column if not exists ${cm("kind")} text not null default 'message' check (${cm("kind")} in ('message', 'note'));
${inboxDetailsDdl(q)}

do $$
begin
  if to_regclass(${sqlString(messages)}) is null then
    return;
  end if;
  if to_regclass(${sqlString(files)}) is null
    and exists (select 1 from ${messages} x where x.attachments <> '[]'::jsonb) then
    raise exception 'inbox: messages have files and the attachments table is missing'
      using hint = 'apply the attachments module first, then run sql upgrade again';
  end if;
  insert into ${conv} (${[cc("id"), cc("tenant"), cc("kind"), cc("access"), cc("lastMessageAt"), cc("createdAt")].join(", ")})
  select v.${cv("id")}, v.${cv("tenant")}, 'inbox', 'tenant', v.${cv("lastMessageAt")}, v.${cv("createdAt")}
  from ${q.t("conversations")} v
  on conflict do nothing;
  insert into ${msg} (${[cm("id"), cm("tenant"), cm("conversation"), cm("author"), cm("kind"), cm("body"), cm("mentions"), cm("sentAt"), cm("editedAt"), cm("deletedAt"), cm("createdAt")].join(", ")})
  select x.id, x.tenant_id, x.conversation_id, x.author_id, x.kind, left(x.body, ${String(m.maxBody)}), x.mentions, x.created_at, x.edited_at, x.deleted_at, x.created_at
  from ${messages} x
  order by x.created_at, x.id
  on conflict do nothing;
  insert into ${q.t("details")} (${[dt("message"), dt("tenant"), dt("conversation"), dt("direction"), dt("authorType"), dt("format"), dt("externalId"), dt("replyTo"), dt("metadata")].join(", ")})
  select x.id, x.tenant_id, x.conversation_id, x.direction, x.author_type, x.format, x.external_id, x.reply_to, x.metadata
  from ${messages} x
  on conflict do nothing;
  insert into ${members} as k (${ck("conversation")}, ${ck("tenant")}, ${ck("user")}, ${ck("lastReadAt")})
  select u.conversation, v.${cv("tenant")}, u.member, max(u.read_at)
  from (
    select p.conversation_id as conversation, p.user_id as member, null::timestamptz as read_at from ${old("conversation_participants")} p
    union all
    select r.conversation_id, r.user_id, r.last_read_at from ${old("conversation_reads")} r
    union all
    select x.conversation_id, x.author_id, null from ${messages} x where x.author_id is not null
    union all
    select w.${cv("id")}, c.${ct("user")}, null from ${q.t("conversations")} w
    join ${q.t("contacts")} c on c.${ct("id")} = w.${cv("contact")} where c.${ct("user")} is not null
  ) u
  join ${q.t("conversations")} v on v.${cv("id")} = u.conversation
  where exists (select 1 from auth.users z where z.id = u.member)
  group by u.conversation, v.${cv("tenant")}, u.member
  on conflict (${ck("conversation")}, ${ck("user")}) do update
    set ${ck("lastReadAt")} = greatest(k.${ck("lastReadAt")}, excluded.${ck("lastReadAt")});
  if to_regclass(${sqlString(files)}) is not null then
    insert into ${files} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("name")}, ${a("mimeType")}, ${a("size")}, ${a("uploadedBy")}, ${a("detail")}, ${a("createdAt")})
    select x.tenant_id, ${core.message}, x.id::text,
      left(coalesce(nullif(f ->> 'name', ''), 'file'), 255),
      case when lower(f ->> 'content_type') ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$' then lower(f ->> 'content_type') else 'application/octet-stream' end,
      coalesce((f ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', case when f ? 'path'
        then jsonb_build_object('bucket', ${sqlString(q.bucket)}, 'path', f ->> 'path', 'name', f ->> 'name', 'content_type', f ->> 'content_type', 'size', f -> 'size')
        else f end)::text,
      x.created_at
    from ${messages} x
    cross join lateral jsonb_array_elements(x.attachments) f
    where x.deleted_at is null and jsonb_typeof(f) = 'object' and (f ? 'path' or f ? 'url');
  end if;
${reactions}
  drop table if exists ${old("inbox_mentions")} cascade;
  drop table if exists ${old("conversation_reads")} cascade;
  drop table if exists ${old("conversation_participants")} cascade;
  drop table ${messages} cascade;
  alter table ${q.t("conversations")} alter column ${cv("id")} drop default;
end;
$$;
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists ${ctx.trigger("inbox_files_read")} on storage.objects;
    drop policy if exists ${ctx.trigger("inbox_files_write")} on storage.objects;
  end if;
end;
$$;
${LEGACY_FUNCTIONS.map((signature) => `drop function if exists ${ctx.schema}.${signature};`).join("\n")}`;
  },
};

function contract(): readonly BlockSqlContractFunction[] {
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
    { name: "send_inbox_message", args: ["uuid", "jsonb"], returns: "jsonb" },
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
    { name: "mark_conversation_read", args: ["uuid"], returns: "timestamptz" },
    {
      name: "react_to_inbox_message",
      args: ["uuid", "text", "boolean", "text"],
      returns: "jsonb",
    },
    {
      name: "create_inbox_attachment",
      args: ["uuid", "text", "text", "bigint"],
      returns: "jsonb",
    },
    {
      name: "edit_inbox_message",
      args: ["uuid", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "list_inbox_conversations",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_conversation", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_inbox_messages",
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
      name: "schedule_inbox_message",
      args: ["uuid", "jsonb", "timestamptz"],
      returns: "jsonb",
    },
    { name: "list_scheduled_inbox_messages", args: ["uuid"], returns: "jsonb" },
    {
      name: "reschedule_inbox_message",
      args: ["uuid", "timestamptz"],
      returns: "jsonb",
    },
    { name: "cancel_inbox_message", args: ["uuid"], returns: "boolean" },
    {
      name: "publish_due_inbox_messages",
      args: ["integer"],
      returns: "integer",
    },
    {
      name: "upsert_message_template",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_message_template", args: ["uuid"], returns: "boolean" },
    { name: "purge_contact", args: ["uuid"], returns: "jsonb" },
    { name: "get_inbox_message", args: ["uuid"], returns: "jsonb" },
    { name: "pending_inbox_files", args: ["integer"], returns: "jsonb" },
    { name: "inbox_file_failed", args: ["uuid", "text"], returns: "boolean" },
  ];
}

export const INBOX: BlockSqlDefinition = {
  internal: [
    "inbox_contact_ids",
    "inbox_conversation_allowed",
    "inbox_note_readable",
    "inbox_can_conversation",
    "inbox_conversation_json",
    "inbox_messages_json",
    "inbox_contact_read_at",
    "inbox_resolve_contact",
    "inbox_add_message",
    "inbox_file_allowed",
    "inbox_message_broadcast",
    "inbox_conversation_broadcast",
    "inbox_delivery_broadcast",
  ],
  name: "inbox",
  scopes: ["tenant"],
  title: "Shared inbox",
  description:
    "Conversations with contacts across the in-app widget and chat channels, on the messaging core: inboxes, members and teams, contacts with their channel identities, messages and internal notes with scanned files, mentions, assignment, bot hand-off, read state, delivery status, stored webhook events and message templates. Staff read with inbox.read; contacts read their own conversations without the notes; Realtime pings carry ids only.",
  requires: [
    "memberships",
    "permissions",
    "updated-at",
    "teams",
    "messaging",
    "attachments",
  ],
  integrates: [
    "queue",
    "notifications",
    "reactions",
    "data-lifecycle",
    "automations",
    "tasks",
  ],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
  upgrades: [
    {
      from: 1,
      description:
        "purge_inbound_events keeps events for the data-lifecycle retention policy and skips those under a legal hold.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "The functions whose names the messaging block owns are send_inbox_message, edit_inbox_message, get_inbox_message, list_inbox_messages, list_inbox_conversations and set_inbox_typing.",
      sql: renamedFunctions,
    },
    TO_MESSAGING,
  ],
  names: INBOX_NAMES,
  contract,
  build,
  data: (ctx) =>
    shippedAutomation(ctx, CONVERSATION_TO_TASK, {
      module: "tasks",
      singular: "work_item",
    }),
  topics: (ctx) => {
    const { topic } = inboxSql(ctx);

    return [`${topic}:org:{organizationId}`];
  },
};
