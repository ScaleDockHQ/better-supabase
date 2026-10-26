import type { InboxSql } from "./inbox-names.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { updatedAt, lockTable } from "../shared.ts";
import { topics } from "./inbox-names.ts";

const CHANNELS = [
  "in_app",
  "email",
  "slack",
  "teams",
  "discord",
  "telegram",
  "whatsapp",
  "messenger",
  "instagram",
  "sms",
  "github",
  "linear",
  "other",
] as const;

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

const policy = (table: string, name: string, using: string): string =>
  renderPolicy(
    makePolicy({
      table,
      name,
      command: "select",
      roles: ["authenticated"],
      using,
    }),
    { drop: true, target: table },
  );

/** An optional column's line, followed by a comma, or nothing. */
const line = (
  q: InboxSql,
  table: string,
  column: string,
  type: () => string,
): string =>
  q.has(table, column) ? `\n  ${q.cols(table)(column)} ${type()},` : "";

/** An optional last column's line, after the comma it needs, or nothing. */
const tail = (
  q: InboxSql,
  table: string,
  column: string,
  type: () => string,
): string =>
  q.has(table, column) ? `,\n  ${q.cols(table)(column)} ${type()}` : "";

/**
 * The unique index an `on conflict` target needs on the app's table, where the
 * render drops the module's primary key and unique constraints.
 */
const unique = (
  q: InboxSql,
  table: string,
  what: string,
  columns: readonly string[],
): string =>
  q.ctx.owns(table)
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${q.ctx.tableName(table).name}_${what}_key`)} on ${q.t(table)} (${columns.map(q.cols(table)).join(", ")});`;

/**
 * The inbox's own fields of a core message: its direction, who wrote it and the
 * channel's id for it. The message itself lives in the messaging core.
 */
export function inboxDetailsDdl(q: InboxSql): string {
  const dt = q.cols("details");
  const cv = q.cols("conversations");
  const table = q.t("details");

  return `create table if not exists ${table} (
  ${dt("message")} uuid primary key,
  ${dt("tenant")} ${q.id} not null,
  ${dt("conversation")} uuid not null references ${q.t("conversations")} (${cv("id")}) on delete cascade,
  ${dt("direction")} text not null check (${dt("direction")} in ('inbound', 'outbound')),
  ${dt("authorType")} text not null check (${dt("authorType")} in ('contact', 'agent', 'bot', 'system')),${line(q, "details", "format", () => `text not null default 'text' check (${dt("format")} in ('text', 'markdown'))`)}
  ${dt("externalId")} text${tail(q, "details", "replyTo", () => "uuid")}${tail(q, "details", "metadata", () => "jsonb not null default '{}'::jsonb")}
);
create unique index if not exists ${q.ctx.naming.rename("inbox_message_details_external_idx")} on ${table} (${dt("conversation")}, ${dt("externalId")}) where ${dt("externalId")} is not null;
create index if not exists ${q.ctx.naming.rename("inbox_message_details_conversation_idx")} on ${table} (${dt("conversation")});
${q.has("details", "replyTo") ? `create index if not exists ${q.ctx.naming.rename("inbox_message_details_reply_idx")} on ${table} (${dt("replyTo")}) where ${dt("replyTo")} is not null;` : ""}`;
}

/** Tables, indexes, grants and read policies. Writes go through functions. */
export function inboxTables(q: InboxSql, sharedTeams = false): string {
  const { id } = q;
  const ib = q.cols("inboxes");
  const mb = q.cols("members");
  const tm = q.cols("teams");
  const tmm = q.cols("teamMembers");
  const ct = q.cols("contacts");
  const ci = q.cols("identities");
  const cv = q.cols("conversations");
  const ev = q.cols("events");
  const dt = q.cols("details");
  const dl = q.cols("deliveries");
  const ie = q.cols("inbound");
  const tp = q.cols("templates");
  const sm = q.cols("scheduled");

  const T = {
    inboxes: q.t("inboxes"),
    members: q.t("members"),
    teams: q.t("teams"),
    teamMembers: q.t("teamMembers"),
    contacts: q.t("contacts"),
    identities: q.t("identities"),
    conversations: q.t("conversations"),
    events: q.t("events"),
    details: q.t("details"),
    deliveries: q.t("deliveries"),
    inbound: q.t("inbound"),
    templates: q.t("templates"),
    scheduled: q.t("scheduled"),
  };

  const botModes = list(["bot", "human", "paused"]);

  return `-- Inboxes: one per channel address (the in-app widget, a WhatsApp number, a
-- Slack workspace) in a tenant. bot_mode is the default for new
-- conversations: bot (the bot answers), human (staff answer) or paused.
create table if not exists ${T.inboxes} (
  ${ib("id")} uuid primary key default gen_random_uuid(),
  ${ib("tenant")} ${id} not null,
  ${ib("name")} text not null check (length(${ib("name")}) between 1 and 200),
  ${ib("channel")} text not null default 'in_app' check (${ib("channel")} in (${list(CHANNELS)})),${line(q, "inboxes", "address", () => "text")}${line(q, "inboxes", "installation", () => "uuid")}
  ${ib("botMode")} text not null default 'human' check (${ib("botMode")} in (${botModes}))${tail(q, "inboxes", "settings", () => `jsonb not null default '{}'::jsonb check (jsonb_typeof(${ib("settings")}) = 'object')`)}${tail(q, "inboxes", "createdAt", () => "timestamptz not null default now()")}${tail(q, "inboxes", "archivedAt", () => "timestamptz")}
);
create index if not exists ${q.ctx.naming.rename("inboxes_tenant_idx")} on ${T.inboxes} (${ib("tenant")});
${q.has("inboxes", "address") ? `create unique index if not exists ${q.ctx.naming.rename("inboxes_address_idx")} on ${T.inboxes} (${ib("channel")}, ${ib("address")}) where ${ib("address")} is not null${q.has("inboxes", "archivedAt") ? ` and ${ib("archivedAt")} is null` : ""};\n` : ""}${updatedAt(T.inboxes, ib("updatedAt"))}
${lockTable(T.inboxes, { read: true })}
${policy(T.inboxes, q.ctx.naming.rename("inboxes_staff_read"), q.staff(ib("tenant")))}

create table if not exists ${T.members} (
  ${mb("inbox")} uuid not null references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${mb("user")} uuid not null references auth.users (id) on delete cascade,
  ${mb("role")} text not null default 'agent' check (${mb("role")} in ('agent', 'lead')),${line(q, "members", "createdAt", () => "timestamptz not null default now()")}
  primary key (${mb("inbox")}, ${mb("user")})
);${unique(q, "members", "user", ["inbox", "user"])}
create index if not exists ${q.ctx.naming.rename("inbox_members_user_idx")} on ${T.members} (${mb("user")});
${lockTable(T.members, { read: true })}
${policy(T.members, q.ctx.naming.rename("inbox_members_staff_read"), `exists (select 1 from ${T.inboxes} i where i.${ib("id")} = ${mb("inbox")} and ${q.staff(`i.${ib("tenant")}`)})`)}

${
  sharedTeams
    ? "-- Teams live in the teams module. Assignment stores that module's id."
    : `create table if not exists ${T.teams} (
  ${tm("id")} uuid primary key default gen_random_uuid(),
  ${tm("tenant")} ${id} not null,
  ${tm("name")} text not null check (length(${tm("name")}) between 1 and 200),${line(q, "teams", "createdAt", () => "timestamptz not null default now()")}
  unique (${tm("tenant")}, ${tm("name")})
);
${lockTable(T.teams, { read: true })}
${policy(T.teams, q.ctx.naming.rename("inbox_teams_staff_read"), q.staff(tm("tenant")))}

create table if not exists ${T.teamMembers} (
  ${tmm("team")} uuid not null references ${T.teams} (${tm("id")}) on delete cascade,
  ${tmm("user")} uuid not null references auth.users (id) on delete cascade,${line(q, "teamMembers", "createdAt", () => "timestamptz not null default now()")}
  primary key (${tmm("team")}, ${tmm("user")})
);${unique(q, "teamMembers", "user", ["team", "user"])}
create index if not exists inbox_team_members_user_idx on ${T.teamMembers} (${tmm("user")});
${lockTable(T.teamMembers, { read: true })}
${policy(T.teamMembers, q.ctx.naming.rename("inbox_team_members_staff_read"), `exists (select 1 from ${T.teams} t where t.${tm("id")} = ${tmm("team")} and ${q.staff(`t.${tm("tenant")}`)})`)}`
}

-- The people staff talk to. user_id links a signed-in widget visitor (an
-- anonymous Auth user works too) to their contact.
create table if not exists ${T.contacts} (
  ${ct("id")} uuid primary key default gen_random_uuid(),
  ${ct("tenant")} ${id} not null,
  ${ct("user")} uuid references auth.users (id) on delete set null${tail(q, "contacts", "name", () => `text check (length(${ct("name")}) <= 200)`)}${tail(q, "contacts", "email", () => `text check (length(${ct("email")}) <= 320)`)}${tail(q, "contacts", "phone", () => `text check (length(${ct("phone")}) <= 50)`)}${tail(q, "contacts", "avatarUrl", () => "text")}${tail(q, "contacts", "metadata", () => "jsonb not null default '{}'::jsonb")}${tail(q, "contacts", "createdAt", () => "timestamptz not null default now()")}
);
create unique index if not exists contacts_user_idx on ${T.contacts} (${ct("tenant")}, ${ct("user")}) where ${ct("user")} is not null;
${q.has("contacts", "email") ? `create index if not exists contacts_email_idx on ${T.contacts} (${ct("tenant")}, lower(${ct("email")}));\n` : ""}create index if not exists contacts_user_id_idx on ${T.contacts} (${ct("user")});
${updatedAt(T.contacts, ct("updatedAt"))}
${lockTable(T.contacts, { read: true })}
${policy(T.contacts, q.ctx.naming.rename("contacts_read"), `${q.staff(ct("tenant"))} or ${ct("user")} = (select auth.uid())`)}

-- A contact's address on a channel: a WhatsApp number, a Slack user id.
create table if not exists ${T.identities} (
  ${ci("id")} uuid primary key default gen_random_uuid(),
  ${ci("tenant")} ${id} not null,
  ${ci("contact")} uuid not null references ${T.contacts} (${ct("id")}) on delete cascade,
  ${ci("channel")} text not null check (length(${ci("channel")}) between 1 and 50),
  ${ci("externalId")} text not null check (length(${ci("externalId")}) between 1 and 500),${line(q, "identities", "createdAt", () => "timestamptz not null default now()")}
  unique (${ci("tenant")}, ${ci("channel")}, ${ci("externalId")})
);${unique(q, "identities", "external", ["tenant", "channel", "externalId"])}
create index if not exists contact_identities_contact_idx on ${T.identities} (${ci("contact")});
${lockTable(T.identities, { read: true })}
${policy(T.identities, q.ctx.naming.rename("contact_identities_staff_read"), q.staff(ci("tenant")))}

-- The inbox side of a core conversation of kind inbox, with the same id:
-- one per channel thread (thread_id is the Chat SDK thread id), reopened
-- when the contact writes again. last_message_at and the preview follow the
-- messages, never the notes.
create table if not exists ${T.conversations} (
  ${cv("id")} uuid primary key,
  ${cv("tenant")} ${id} not null,
  ${cv("inbox")} uuid not null references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${cv("contact")} uuid not null references ${T.contacts} (${ct("id")}) on delete cascade,${line(q, "conversations", "subject", () => `text check (length(${cv("subject")}) <= 500)`)}
  ${cv("status")} text not null default 'open' check (${cv("status")} in ('open', 'pending', 'snoozed', 'resolved')),${line(q, "conversations", "priority", () => `text not null default 'normal' check (${cv("priority")} in ('low', 'normal', 'high', 'urgent'))`)}
  ${cv("assignee")} uuid references auth.users (id) on delete set null,
  ${cv("team")} uuid${sharedTeams ? "" : ` references ${T.teams} (${tm("id")}) on delete set null`},
  ${cv("botMode")} text not null default 'human' check (${cv("botMode")} in (${botModes})),
  ${cv("thread")} text,
  ${cv("snoozedUntil")} timestamptz,
  ${cv("lastMessageAt")} timestamptz not null default now(),${line(q, "conversations", "preview", () => "text")}${line(q, "conversations", "firstResponseAt", () => "timestamptz")}${line(q, "conversations", "resolvedAt", () => "timestamptz")}${line(q, "conversations", "metadata", () => "jsonb not null default '{}'::jsonb")}
  ${cv("createdAt")} timestamptz not null default now()
);
create unique index if not exists conversations_thread_idx on ${T.conversations} (${cv("inbox")}, ${cv("thread")}) where ${cv("thread")} is not null;
create index if not exists conversations_list_idx on ${T.conversations} (${cv("tenant")}, ${cv("status")}, ${cv("lastMessageAt")} desc, ${cv("id")});
create index if not exists conversations_assignee_idx on ${T.conversations} (${cv("assignee")}) where ${cv("assignee")} is not null;
create index if not exists conversations_contact_idx on ${T.conversations} (${cv("contact")});
create index if not exists ${q.ctx.naming.rename("conversations_inbox_idx")} on ${T.conversations} (${cv("inbox")});
create index if not exists conversations_team_idx on ${T.conversations} (${cv("team")}) where ${cv("team")} is not null;
${updatedAt(T.conversations, cv("updatedAt"))}
${lockTable(T.conversations, { read: true })}

-- The activity of a conversation: assignments, status and bot hand-offs.
create table if not exists ${T.events} (
  ${ev("id")} bigint generated always as identity primary key,
  ${ev("tenant")} ${id} not null,
  ${ev("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${ev("type")} text not null check (${ev("type")} ~ '^[a-z][a-z0-9_]{0,40}$'),${line(q, "events", "actor", () => "uuid references auth.users (id) on delete set null")}${line(q, "events", "data", () => "jsonb not null default '{}'::jsonb")}
  ${ev("createdAt")} timestamptz not null default clock_timestamp()
);
create index if not exists conversation_events_conversation_idx on ${T.events} (${ev("conversation")}, ${ev("id")});
${q.has("events", "actor") ? `create index if not exists conversation_events_actor_idx on ${T.events} (${ev("actor")});\n` : ""}${lockTable(T.events, { read: true })}
${policy(T.events, q.ctx.naming.rename("conversation_events_staff_read"), q.staff(ev("tenant")))}

${inboxDetailsDdl(q)}
${lockTable(T.details, { read: true })}
${policy(T.details, q.ctx.naming.rename("inbox_message_details_staff_read"), q.staff(dt("tenant")))}

-- What happened to an outbound message on its channel. Status only moves
-- forward: queued, sent, delivered, read; failed before delivery.
create table if not exists ${T.deliveries} (
  ${dl("id")} uuid primary key default gen_random_uuid(),
  ${dl("tenant")} ${id} not null,
  ${dl("message")} uuid not null references ${T.details} (${dt("message")}) on delete cascade,
  ${dl("channel")} text not null,
  ${dl("status")} text not null default 'queued' check (${dl("status")} in ('queued', 'sent', 'delivered', 'read', 'failed')),
  ${dl("externalId")} text,${line(q, "deliveries", "error", () => "text")}${line(q, "deliveries", "attempts", () => "integer not null default 0")}
  ${dl("createdAt")} timestamptz not null default now(),
  unique (${dl("message")}, ${dl("channel")})
);${unique(q, "deliveries", "channel", ["message", "channel"])}
create index if not exists message_deliveries_external_idx on ${T.deliveries} (${dl("channel")}, ${dl("externalId")}) where ${dl("externalId")} is not null;
${updatedAt(T.deliveries, dl("updatedAt"))}
${lockTable(T.deliveries, { read: true })}
${policy(T.deliveries, q.ctx.naming.rename("message_deliveries_staff_read"), q.staff(dl("tenant")))}

-- Webhook deliveries from the channels, stored before the ack so a slow or
-- failed handler loses nothing. external_id dedupes a platform's retries.
create table if not exists ${T.inbound} (
  ${ie("id")} uuid primary key default gen_random_uuid(),
  ${ie("tenant")} ${id},
  ${ie("adapter")} text not null check (length(${ie("adapter")}) between 1 and 100),
  ${ie("externalId")} text,
  ${ie("inbox")} uuid references ${T.inboxes} (${ib("id")}) on delete set null,
  ${ie("headers")} jsonb not null default '{}'::jsonb,
  ${ie("body")} text not null,
  ${ie("status")} text not null default 'received' check (${ie("status")} in ('received', 'processed', 'ignored', 'failed')),${line(q, "inbound", "error", () => "text")}
  ${ie("attempts")} integer not null default 0,
  ${ie("receivedAt")} timestamptz not null default now()${tail(q, "inbound", "processedAt", () => "timestamptz")}
);
create unique index if not exists inbound_events_external_idx on ${T.inbound} (${ie("adapter")}, ${ie("externalId")}) where ${ie("externalId")} is not null;
create index if not exists inbound_events_status_idx on ${T.inbound} (${ie("status")}, ${ie("receivedAt")});
create index if not exists ${q.ctx.naming.rename("inbound_events_inbox_idx")} on ${T.inbound} (${ie("inbox")});
${lockTable(T.inbound)}

-- Approved templates for channels that need one outside a reply window
-- (WhatsApp after 24 hours). external_id is the platform's template name.
create table if not exists ${T.templates} (
  ${tp("id")} uuid primary key default gen_random_uuid(),
  ${tp("tenant")} ${id} not null,
  ${tp("inbox")} uuid references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${tp("name")} text not null check (length(${tp("name")}) between 1 and 200),
  ${tp("channel")} text not null,
  ${tp("language")} text not null default 'en',
  ${tp("body")} text not null,${line(q, "templates", "variables", () => `jsonb not null default '[]'::jsonb check (jsonb_typeof(${tp("variables")}) = 'array')`)}${line(q, "templates", "externalId", () => "text")}
  ${tp("createdAt")} timestamptz not null default now(),
  unique (${tp("tenant")}, ${tp("channel")}, ${tp("name")}, ${tp("language")})
);${unique(q, "templates", "name", ["tenant", "channel", "name", "language"])}
create index if not exists ${q.ctx.naming.rename("message_templates_inbox_idx")} on ${T.templates} (${tp("inbox")});
${updatedAt(T.templates, tp("updatedAt"))}
${lockTable(T.templates, { read: true })}
${policy(T.templates, q.ctx.naming.rename("message_templates_staff_read"), q.staff(tp("tenant")))}

-- Staff replies to send later. publish_due_inbox_messages sends each one
-- through the normal reply path once scheduled_for passes; until then only
-- its author sees it.
create table if not exists ${T.scheduled} (
  ${sm("id")} uuid primary key default gen_random_uuid(),
  ${sm("tenant")} ${id} not null,
  ${sm("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${sm("author")} uuid not null references auth.users (id) on delete cascade,
  ${sm("input")} jsonb not null check (jsonb_typeof(${sm("input")}) = 'object'),
  ${sm("scheduledFor")} timestamptz not null${tail(q, "scheduled", "createdAt", () => "timestamptz not null default now()")}
);
create index if not exists ${q.ctx.naming.rename("scheduled_inbox_messages_due_idx")} on ${T.scheduled} (${sm("scheduledFor")});
create index if not exists ${q.ctx.naming.rename("scheduled_inbox_messages_conversation_idx")} on ${T.scheduled} (${sm("conversation")});
create index if not exists ${q.ctx.naming.rename("scheduled_inbox_messages_author_idx")} on ${T.scheduled} (${sm("author")}, ${sm("scheduledFor")});
${updatedAt(T.scheduled, sm("updatedAt"))}
${lockTable(T.scheduled, { read: true })}
${policy(T.scheduled, q.ctx.naming.rename("scheduled_inbox_messages_author_read"), `${sm("author")} = (select auth.uid()) and ${q.staff(sm("tenant"), "reply")}`)}`;
}

/**
 * The caller's contacts and conversations, the policy that uses them, and the
 * checks the messaging core calls for a conversation of kind inbox.
 */
export function inboxHelpers(q: InboxSql): string {
  const ct = q.cols("contacts");
  const cv = q.cols("conversations");

  const contactIds = `(select ${q.fn("inbox_contact_ids")}())`;

  const internal = (signature: string, roles: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to ${roles};`;

  return `create or replace function ${q.fn("inbox_contact_ids")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.${ct("id")} from ${q.t("contacts")} c where c.${ct("user")} = (select auth.uid());
$$;
${internal(`${q.fn("inbox_contact_ids")}()`, "authenticated, service_role")}

-- Whether the caller may see a conversation: staff of its tenant, or the
-- signed-in contact it belongs to. write asks for the reply key instead.
create or replace function ${q.fn("inbox_conversation_allowed")}(conversation text, write boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${q.service} or coalesce((
    select (case when write then ${q.can(`v.${cv("tenant")}`, "reply")} else ${q.can(`v.${cv("tenant")}`, "read")} end)
      or exists (select 1 from ${q.t("contacts")} c where c.${ct("id")} = v.${cv("contact")} and c.${ct("user")} = (select auth.uid()))
    from ${q.t("conversations")} v
    where v.${cv("id")}::text = conversation
  ), false);
$$;
${internal(`${q.fn("inbox_conversation_allowed")}(text, boolean)`, "authenticated, service_role")}

-- Whether the caller reads the conversation's internal notes: staff of its
-- tenant, never the contact.
create or replace function ${q.fn("inbox_note_readable")}(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${q.service} or exists (
    select 1 from ${q.t("conversations")} v
    where v.${cv("id")} = inbox_note_readable.conversation and ${q.can(`v.${cv("tenant")}`, "read")}
  );
$$;
${internal(`${q.fn("inbox_note_readable")}(uuid)`, "authenticated, service_role")}

-- What the messaging core's can_conversation answers for a conversation of
-- kind inbox: read for staff and the contact, send for repliers and the
-- contact (typing included), moderate for the manage key.
create or replace function ${q.fn("inbox_can_conversation")}(conversation uuid, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case inbox_can_conversation.action
    when 'read' then
      return ${q.fn("inbox_conversation_allowed")}(inbox_can_conversation.conversation::text);
    when 'send' then
      return ${q.fn("inbox_conversation_allowed")}(inbox_can_conversation.conversation::text, true);
    when 'moderate' then
      return exists (
        select 1 from ${q.t("conversations")} v
        where v.${cv("id")} = inbox_can_conversation.conversation and ${q.can(`v.${cv("tenant")}`, "manage")}
      );
    else
      return false;
  end case;
end;
$$;
${internal(`${q.fn("inbox_can_conversation")}(uuid, text)`, "authenticated, service_role")}

${policy(q.t("conversations"), "conversations_read", `${q.staff(cv("tenant"))} or ${cv("contact")} in ${contactIds}`)}`;
}

/**
 * Realtime pings with ids only. The messaging core pings each message on its
 * conversation topic; the inbox adds conversation changes there and every
 * change on `<topic>:org:<tenant>` for staff. Deliveries go to the staff topic
 * only.
 */
export function inboxRealtime(q: InboxSql): string {
  const cv = q.cols("conversations");
  const dt = q.cols("details");
  const dl = q.cols("deliveries");
  const ms = q.core.cols("messages");
  const topic = topics(q);

  const send = (payload: string, event: string, to: string): string =>
    `perform realtime.send(${payload}, ${event}, ${to}, true);`;

  const ready = `to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null`;
  const receive = q.ctx.trigger("inbox_receive");
  const broadcast = q.ctx.trigger("inbox_broadcast");

  return `-- A core message in an inbox conversation pings the staff topic. The
-- messaging module attaches it to its messages table.
create or replace function ${q.fn("inbox_message_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
begin
  if not ${ready} or new.${ms("sentAt")} is null then
    return null;
  end if;
  select v.${cv("tenant")}::text into v_tenant from ${q.t("conversations")} v where v.${cv("id")} = new.${ms("conversation")};
  if v_tenant is not null then
    ${send(
      `jsonb_build_object('conversation_id', new.${ms("conversation")}, 'message_id', new.${ms("id")}, 'kind', new.${ms("kind")})`,
      `case when tg_op = 'INSERT' or old.${ms("sentAt")} is null then 'message' else 'message_updated' end`,
      topic.org("v_tenant"),
    )}
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_message_broadcast")}() from public, anon, authenticated;

create or replace function ${q.fn("inbox_conversation_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new.${cv("id")});
begin
  if ${ready} then
    ${send("v_payload", "'conversation'", q.core.topic(`new.${cv("id")}`))}
    ${send("v_payload", "'conversation'", topic.org(`new.${cv("tenant")}`))}
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_conversation_broadcast")}() from public, anon, authenticated;
drop trigger if exists conversations_broadcast on ${q.t("conversations")};
create trigger conversations_broadcast after insert or update on ${q.t("conversations")}
  for each row execute function ${q.fn("inbox_conversation_broadcast")}();

create or replace function ${q.fn("inbox_delivery_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${ready} then
    perform realtime.send(
      jsonb_build_object('conversation_id', d.${dt("conversation")}, 'message_id', new.${dl("message")}, 'status', new.${dl("status")}),
      'delivery',
      ${topic.org(`new.${dl("tenant")}`)},
      true
    )
    from ${q.t("details")} d where d.${dt("message")} = new.${dl("message")};
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_delivery_broadcast")}() from public, anon, authenticated;
drop trigger if exists message_deliveries_broadcast on ${q.t("deliveries")};
create trigger message_deliveries_broadcast after insert or update of ${dl("status")} on ${q.t("deliveries")}
  for each row execute function ${q.fn("inbox_delivery_broadcast")}();

-- Staff join ${q.topic}:org:<tenant>. A conversation's own topic, with typing
-- and presence, is the messaging core's.
do $$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: receive,
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${q.topic}:org:%`)}
        and substr((select realtime.topic()), ${String(q.topic.length + 6)}) in (select x::text from ${q.ctx.scope.ids(q.key("read"))} x)`,
          }),
          { drop: true, target: "realtime.messages" },
        )}
    drop policy if exists ${broadcast} on realtime.messages;
  end if;
end;
$$;`;
}

/**
 * Downloads of a message's files: the attachments module's own policy covers
 * staff, and this one lets the conversation's contact read the clean files of
 * the messages they see.
 */
export function inboxStorage(q: InboxSql): string {
  const read = q.ctx.trigger("inbox_files_read");
  const write = q.ctx.trigger("inbox_files_write");
  const at = q.ctx.of("attachments");
  const a = (column: string): string => at.col("attachments", column);
  const ms = q.core.cols("messages");
  const dt = q.cols("details");

  return `create or replace function ${q.fn("inbox_file_allowed")}(bucket text, object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from ${at.table("attachments")} a
    join ${q.core.t("messages")} m on a.${a("subjectType")} = ${q.core.message} and m.${ms("id")}::text = a.${a("subjectId")}
    join ${q.t("details")} d on d.${dt("message")} = m.${ms("id")}
    where a.${a("bucket")} = inbox_file_allowed.bucket and a.${a("path")} = inbox_file_allowed.object_name
      and a.${a("status")} = 'clean'
      and m.${ms("deletedAt")} is null
      and ${q.fn("inbox_conversation_allowed")}(d.${dt("conversation")}::text)
      and (m.${ms("kind")} = 'message' or ${q.fn("inbox_note_readable")}(d.${dt("conversation")}))
  );
end;
$$;
revoke execute on function ${q.fn("inbox_file_allowed")}(text, text) from public, anon;
grant execute on function ${q.fn("inbox_file_allowed")}(text, text) to authenticated, service_role;

do $$
begin
  if to_regclass('storage.objects') is not null then
        ${renderPolicy(makePolicy({ table: "storage.objects", name: read, command: "select", roles: ["authenticated"], using: `${q.fn("inbox_file_allowed")}(bucket_id, name)` }), { drop: true, target: "storage.objects" })}
    drop policy if exists ${write} on storage.objects;
  end if;
end;
$$;`;
}
