import type { InboxSql } from "./inbox-names.ts";

import { sqlString } from "../../core/template.ts";
import { updatedAt } from "../shared.ts";
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

/** Tables, indexes, grants and read policies. Writes go through functions. */
export function inboxTables(q: InboxSql): string {
  const { id } = q;
  const ib = q.cols("inboxes");
  const mb = q.cols("members");
  const tm = q.cols("teams");
  const tmm = q.cols("teamMembers");
  const ct = q.cols("contacts");
  const ci = q.cols("identities");
  const cv = q.cols("conversations");
  const pa = q.cols("participants");
  const ev = q.cols("events");
  const rd = q.cols("reads");
  const ms = q.cols("messages");
  const dl = q.cols("deliveries");
  const mn = q.cols("mentions");
  const ie = q.cols("inbound");
  const tp = q.cols("templates");
  const T = {
    inboxes: q.t("inboxes"),
    members: q.t("members"),
    teams: q.t("teams"),
    teamMembers: q.t("teamMembers"),
    contacts: q.t("contacts"),
    identities: q.t("identities"),
    conversations: q.t("conversations"),
    participants: q.t("participants"),
    events: q.t("events"),
    reads: q.t("reads"),
    messages: q.t("messages"),
    deliveries: q.t("deliveries"),
    mentions: q.t("mentions"),
    inbound: q.t("inbound"),
    templates: q.t("templates"),
  };
  const lock = (
    table: string,
    read: boolean,
  ): string => `alter table ${table} enable row level security;
revoke all on ${table} from anon, authenticated;
${read ? `grant select on ${table} to authenticated;\n` : ""}grant all on ${table} to service_role;`;
  const policy = (table: string, name: string, using: string): string =>
    `drop policy if exists ${name} on ${table};
create policy ${name} on ${table} for select to authenticated
  using (${using});`;
  const botModes = list(["bot", "human", "paused"]);

  return `-- Inboxes: one per channel address (the in-app widget, a WhatsApp number, a
-- Slack workspace) in a tenant. bot_mode is the default for new
-- conversations: bot (the bot answers), human (staff answer) or paused.
create table if not exists ${T.inboxes} (
  ${ib("id")} uuid primary key default gen_random_uuid(),
  ${ib("tenant")} ${id} not null,
  ${ib("name")} text not null check (length(${ib("name")}) between 1 and 200),
  ${ib("channel")} text not null default 'in_app' check (${ib("channel")} in (${list(CHANNELS)})),
  ${ib("address")} text,
  ${ib("installation")} uuid,
  ${ib("botMode")} text not null default 'human' check (${ib("botMode")} in (${botModes})),
  ${ib("settings")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${ib("settings")}) = 'object'),
  ${ib("createdAt")} timestamptz not null default now(),
  ${ib("archivedAt")} timestamptz
);
create index if not exists inboxes_tenant_idx on ${T.inboxes} (${ib("tenant")});
create unique index if not exists inboxes_address_idx on ${T.inboxes} (${ib("channel")}, ${ib("address")}) where ${ib("address")} is not null and ${ib("archivedAt")} is null;
${updatedAt(T.inboxes, ib("updatedAt"))}
${lock(T.inboxes, true)}
${policy(T.inboxes, "inboxes_staff_read", q.staff(ib("tenant")))}

create table if not exists ${T.members} (
  ${mb("inbox")} uuid not null references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${mb("user")} uuid not null references auth.users (id) on delete cascade,
  ${mb("role")} text not null default 'agent' check (${mb("role")} in ('agent', 'lead')),
  ${mb("createdAt")} timestamptz not null default now(),
  primary key (${mb("inbox")}, ${mb("user")})
);
create index if not exists inbox_members_user_idx on ${T.members} (${mb("user")});
${lock(T.members, true)}
${policy(T.members, "inbox_members_staff_read", `exists (select 1 from ${T.inboxes} i where i.${ib("id")} = ${mb("inbox")} and ${q.staff(`i.${ib("tenant")}`)})`)}

create table if not exists ${T.teams} (
  ${tm("id")} uuid primary key default gen_random_uuid(),
  ${tm("tenant")} ${id} not null,
  ${tm("name")} text not null check (length(${tm("name")}) between 1 and 200),
  ${tm("createdAt")} timestamptz not null default now(),
  unique (${tm("tenant")}, ${tm("name")})
);
${lock(T.teams, true)}
${policy(T.teams, "inbox_teams_staff_read", q.staff(tm("tenant")))}

create table if not exists ${T.teamMembers} (
  ${tmm("team")} uuid not null references ${T.teams} (${tm("id")}) on delete cascade,
  ${tmm("user")} uuid not null references auth.users (id) on delete cascade,
  ${tmm("createdAt")} timestamptz not null default now(),
  primary key (${tmm("team")}, ${tmm("user")})
);
create index if not exists inbox_team_members_user_idx on ${T.teamMembers} (${tmm("user")});
${lock(T.teamMembers, true)}
${policy(T.teamMembers, "inbox_team_members_staff_read", `exists (select 1 from ${T.teams} t where t.${tm("id")} = ${tmm("team")} and ${q.staff(`t.${tm("tenant")}`)})`)}

-- The people staff talk to. user_id links a signed-in widget visitor (an
-- anonymous Auth user works too) to their contact.
create table if not exists ${T.contacts} (
  ${ct("id")} uuid primary key default gen_random_uuid(),
  ${ct("tenant")} ${id} not null,
  ${ct("user")} uuid references auth.users (id) on delete set null,
  ${ct("name")} text check (length(${ct("name")}) <= 200),
  ${ct("email")} text check (length(${ct("email")}) <= 320),
  ${ct("phone")} text check (length(${ct("phone")}) <= 50),
  ${ct("avatarUrl")} text,
  ${ct("metadata")} jsonb not null default '{}'::jsonb,
  ${ct("createdAt")} timestamptz not null default now()
);
create unique index if not exists contacts_user_idx on ${T.contacts} (${ct("tenant")}, ${ct("user")}) where ${ct("user")} is not null;
create index if not exists contacts_email_idx on ${T.contacts} (${ct("tenant")}, lower(${ct("email")}));
create index if not exists contacts_user_id_idx on ${T.contacts} (${ct("user")});
${updatedAt(T.contacts, ct("updatedAt"))}
${lock(T.contacts, true)}
${policy(T.contacts, "contacts_read", `${q.staff(ct("tenant"))} or ${ct("user")} = (select auth.uid())`)}

-- A contact's address on a channel: a WhatsApp number, a Slack user id.
create table if not exists ${T.identities} (
  ${ci("id")} uuid primary key default gen_random_uuid(),
  ${ci("tenant")} ${id} not null,
  ${ci("contact")} uuid not null references ${T.contacts} (${ct("id")}) on delete cascade,
  ${ci("channel")} text not null check (length(${ci("channel")}) between 1 and 50),
  ${ci("externalId")} text not null check (length(${ci("externalId")}) between 1 and 500),
  ${ci("createdAt")} timestamptz not null default now(),
  unique (${ci("tenant")}, ${ci("channel")}, ${ci("externalId")})
);
create index if not exists contact_identities_contact_idx on ${T.identities} (${ci("contact")});
${lock(T.identities, true)}
${policy(T.identities, "contact_identities_staff_read", q.staff(ci("tenant")))}

-- One conversation per channel thread (thread_id is the Chat SDK thread id),
-- reopened when the contact writes again.
create table if not exists ${T.conversations} (
  ${cv("id")} uuid primary key default gen_random_uuid(),
  ${cv("tenant")} ${id} not null,
  ${cv("inbox")} uuid not null references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${cv("contact")} uuid not null references ${T.contacts} (${ct("id")}) on delete cascade,
  ${cv("subject")} text check (length(${cv("subject")}) <= 500),
  ${cv("status")} text not null default 'open' check (${cv("status")} in ('open', 'pending', 'snoozed', 'resolved')),
  ${cv("priority")} text not null default 'normal' check (${cv("priority")} in ('low', 'normal', 'high', 'urgent')),
  ${cv("assignee")} uuid references auth.users (id) on delete set null,
  ${cv("team")} uuid references ${T.teams} (${tm("id")}) on delete set null,
  ${cv("botMode")} text not null default 'human' check (${cv("botMode")} in (${botModes})),
  ${cv("thread")} text,
  ${cv("snoozedUntil")} timestamptz,
  ${cv("lastMessageAt")} timestamptz not null default now(),
  ${cv("preview")} text,
  ${cv("firstResponseAt")} timestamptz,
  ${cv("resolvedAt")} timestamptz,
  ${cv("metadata")} jsonb not null default '{}'::jsonb,
  ${cv("createdAt")} timestamptz not null default now()
);
create unique index if not exists conversations_thread_idx on ${T.conversations} (${cv("inbox")}, ${cv("thread")}) where ${cv("thread")} is not null;
create index if not exists conversations_list_idx on ${T.conversations} (${cv("tenant")}, ${cv("status")}, ${cv("lastMessageAt")} desc, ${cv("id")});
create index if not exists conversations_assignee_idx on ${T.conversations} (${cv("assignee")}) where ${cv("assignee")} is not null;
create index if not exists conversations_contact_idx on ${T.conversations} (${cv("contact")});
create index if not exists conversations_inbox_idx on ${T.conversations} (${cv("inbox")});
create index if not exists conversations_team_idx on ${T.conversations} (${cv("team")}) where ${cv("team")} is not null;
${updatedAt(T.conversations, cv("updatedAt"))}
${lock(T.conversations, true)}

create table if not exists ${T.participants} (
  ${pa("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${pa("user")} uuid not null references auth.users (id) on delete cascade,
  ${pa("role")} text not null default 'participant' check (${pa("role")} in ('participant', 'watcher')),
  ${pa("createdAt")} timestamptz not null default now(),
  primary key (${pa("conversation")}, ${pa("user")})
);
create index if not exists conversation_participants_user_idx on ${T.participants} (${pa("user")});
${lock(T.participants, true)}
${policy(T.participants, "conversation_participants_staff_read", `exists (select 1 from ${T.conversations} c where c.${cv("id")} = ${pa("conversation")} and ${q.staff(`c.${cv("tenant")}`)})`)}

-- The activity of a conversation: assignments, status and bot hand-offs.
create table if not exists ${T.events} (
  ${ev("id")} bigint generated always as identity primary key,
  ${ev("tenant")} ${id} not null,
  ${ev("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${ev("type")} text not null check (${ev("type")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${ev("actor")} uuid references auth.users (id) on delete set null,
  ${ev("data")} jsonb not null default '{}'::jsonb,
  ${ev("createdAt")} timestamptz not null default clock_timestamp()
);
create index if not exists conversation_events_conversation_idx on ${T.events} (${ev("conversation")}, ${ev("id")});
create index if not exists conversation_events_actor_idx on ${T.events} (${ev("actor")});
${lock(T.events, true)}
${policy(T.events, "conversation_events_staff_read", q.staff(ev("tenant")))}

create table if not exists ${T.reads} (
  ${rd("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${rd("user")} uuid not null references auth.users (id) on delete cascade,
  ${rd("lastReadAt")} timestamptz not null default now(),
  primary key (${rd("conversation")}, ${rd("user")})
);
create index if not exists conversation_reads_user_idx on ${T.reads} (${rd("user")});
${lock(T.reads, true)}
${policy(T.reads, "conversation_reads_own", `${rd("user")} = (select auth.uid())`)}

-- Messages and internal notes. Contacts read the messages of their own
-- conversations, never the notes.
create table if not exists ${T.messages} (
  ${ms("id")} uuid primary key default gen_random_uuid(),
  ${ms("tenant")} ${id} not null,
  ${ms("conversation")} uuid not null references ${T.conversations} (${cv("id")}) on delete cascade,
  ${ms("direction")} text not null check (${ms("direction")} in ('inbound', 'outbound')),
  ${ms("kind")} text not null default 'message' check (${ms("kind")} in ('message', 'note')),
  ${ms("authorType")} text not null check (${ms("authorType")} in ('contact', 'agent', 'bot', 'system')),
  ${ms("author")} uuid references auth.users (id) on delete set null,
  ${ms("body")} text not null default '' check (length(${ms("body")}) <= ${String(q.maxBody)}),
  ${ms("format")} text not null default 'text' check (${ms("format")} in ('text', 'markdown')),
  ${ms("attachments")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${ms("attachments")}) = 'array'),
  ${ms("reactions")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${ms("reactions")}) = 'object'),
  ${ms("mentions")} uuid[] not null default '{}',
  ${ms("externalId")} text,
  ${ms("replyTo")} uuid references ${T.messages} (${ms("id")}) on delete set null,
  ${ms("metadata")} jsonb not null default '{}'::jsonb,
  -- clock_timestamp keeps a thread in order within one transaction.
  ${ms("createdAt")} timestamptz not null default clock_timestamp(),
  ${ms("editedAt")} timestamptz,
  ${ms("deletedAt")} timestamptz
);
create unique index if not exists inbox_messages_external_idx on ${T.messages} (${ms("conversation")}, ${ms("externalId")}) where ${ms("externalId")} is not null;
create index if not exists inbox_messages_conversation_idx on ${T.messages} (${ms("conversation")}, ${ms("createdAt")}, ${ms("id")});
create index if not exists inbox_messages_author_idx on ${T.messages} (${ms("author")});
create index if not exists inbox_messages_reply_idx on ${T.messages} (${ms("replyTo")}) where ${ms("replyTo")} is not null;
${lock(T.messages, true)}

-- What happened to an outbound message on its channel. Status only moves
-- forward: queued, sent, delivered, read; failed before delivery.
create table if not exists ${T.deliveries} (
  ${dl("id")} uuid primary key default gen_random_uuid(),
  ${dl("tenant")} ${id} not null,
  ${dl("message")} uuid not null references ${T.messages} (${ms("id")}) on delete cascade,
  ${dl("channel")} text not null,
  ${dl("status")} text not null default 'queued' check (${dl("status")} in ('queued', 'sent', 'delivered', 'read', 'failed')),
  ${dl("externalId")} text,
  ${dl("error")} text,
  ${dl("attempts")} integer not null default 0,
  ${dl("createdAt")} timestamptz not null default now(),
  unique (${dl("message")}, ${dl("channel")})
);
create index if not exists message_deliveries_external_idx on ${T.deliveries} (${dl("channel")}, ${dl("externalId")}) where ${dl("externalId")} is not null;
${updatedAt(T.deliveries, dl("updatedAt"))}
${lock(T.deliveries, true)}
${policy(T.deliveries, "message_deliveries_staff_read", q.staff(dl("tenant")))}

create table if not exists ${T.mentions} (
  ${mn("message")} uuid not null references ${T.messages} (${ms("id")}) on delete cascade,
  ${mn("user")} uuid not null references auth.users (id) on delete cascade,
  ${mn("tenant")} ${id} not null,
  ${mn("createdAt")} timestamptz not null default now(),
  primary key (${mn("message")}, ${mn("user")})
);
create index if not exists inbox_mentions_user_idx on ${T.mentions} (${mn("user")}, ${mn("createdAt")} desc);
${lock(T.mentions, true)}
${policy(T.mentions, "inbox_mentions_staff_read", q.staff(mn("tenant")))}

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
  ${ie("status")} text not null default 'received' check (${ie("status")} in ('received', 'processed', 'ignored', 'failed')),
  ${ie("error")} text,
  ${ie("attempts")} integer not null default 0,
  ${ie("receivedAt")} timestamptz not null default now(),
  ${ie("processedAt")} timestamptz
);
create unique index if not exists inbound_events_external_idx on ${T.inbound} (${ie("adapter")}, ${ie("externalId")}) where ${ie("externalId")} is not null;
create index if not exists inbound_events_status_idx on ${T.inbound} (${ie("status")}, ${ie("receivedAt")});
create index if not exists inbound_events_inbox_idx on ${T.inbound} (${ie("inbox")});
${lock(T.inbound, false)}

-- Approved templates for channels that need one outside a reply window
-- (WhatsApp after 24 hours). external_id is the platform's template name.
create table if not exists ${T.templates} (
  ${tp("id")} uuid primary key default gen_random_uuid(),
  ${tp("tenant")} ${id} not null,
  ${tp("inbox")} uuid references ${T.inboxes} (${ib("id")}) on delete cascade,
  ${tp("name")} text not null check (length(${tp("name")}) between 1 and 200),
  ${tp("channel")} text not null,
  ${tp("language")} text not null default 'en',
  ${tp("body")} text not null,
  ${tp("variables")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${tp("variables")}) = 'array'),
  ${tp("externalId")} text,
  ${tp("createdAt")} timestamptz not null default now(),
  unique (${tp("tenant")}, ${tp("channel")}, ${tp("name")}, ${tp("language")})
);
create index if not exists message_templates_inbox_idx on ${T.templates} (${tp("inbox")});
${updatedAt(T.templates, tp("updatedAt"))}
${lock(T.templates, true)}
${policy(T.templates, "message_templates_staff_read", q.staff(tp("tenant")))}`;
}

/** The caller's contacts and conversations, and the policies that use them. */
export function inboxHelpers(q: InboxSql): string {
  const ct = q.cols("contacts");
  const cv = q.cols("conversations");
  const ms = q.cols("messages");
  const policy = (table: string, name: string, using: string): string =>
    `drop policy if exists ${name} on ${table};
create policy ${name} on ${table} for select to authenticated
  using (${using});`;
  const contactIds = `(select ${q.fn("inbox_contact_ids")}())`;
  const contactConversations = `(select ${q.fn("inbox_contact_conversation_ids")}())`;
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

create or replace function ${q.fn("inbox_contact_conversation_ids")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v.${cv("id")} from ${q.t("conversations")} v
  join ${q.t("contacts")} c on c.${ct("id")} = v.${cv("contact")}
  where c.${ct("user")} = (select auth.uid());
$$;
${internal(`${q.fn("inbox_contact_conversation_ids")}()`, "authenticated, service_role")}

-- Whether the caller may see a conversation: staff of its tenant, or the
-- signed-in contact it belongs to. write asks for the reply key instead.
create or replace function ${q.fn("inbox_conversation_allowed")}(conversation text, write boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select (case when write then ${q.can(`v.${cv("tenant")}`, "reply")} else ${q.can(`v.${cv("tenant")}`, "read")} end)
      or exists (select 1 from ${q.t("contacts")} c where c.${ct("id")} = v.${cv("contact")} and c.${ct("user")} = (select auth.uid()))
    from ${q.t("conversations")} v
    where v.${cv("id")}::text = conversation
  ), false);
$$;
${internal(`${q.fn("inbox_conversation_allowed")}(text, boolean)`, "authenticated, service_role")}

${policy(q.t("conversations"), "conversations_read", `${q.staff(cv("tenant"))} or ${cv("contact")} in ${contactIds}`)}
${policy(q.t("messages"), "inbox_messages_read", `${q.staff(ms("tenant"))} or (${ms("kind")} = 'message' and ${ms("conversation")} in ${contactConversations})`)}`;
}

/**
 * Realtime pings with ids only: messages on `<topic>:<conversation>` for
 * staff and the contact, every change on `<topic>:org:<tenant>` for staff.
 * Notes and deliveries go to the staff topic only.
 */
export function inboxRealtime(q: InboxSql): string {
  const cv = q.cols("conversations");
  const ms = q.cols("messages");
  const dl = q.cols("deliveries");
  const ct = q.cols("contacts");
  const rd = q.cols("reads");
  const topic = topics(q);
  const send = (payload: string, event: string, to: string): string =>
    `perform realtime.send(${payload}, ${event}, ${to}, true);`;
  const ready = `to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null`;
  const org = sqlString(`${q.topic}:org:`);
  const prefix = sqlString(`${q.topic}:`);
  const receive = q.ctx.trigger("inbox_receive");
  const broadcast = q.ctx.trigger("inbox_broadcast");
  const allowed = `(
          ((select realtime.topic()) like ${sqlString(`${q.topic}:org:%`)}
            and substr((select realtime.topic()), ${String(q.topic.length + 6)}) in (select x::text from better_supabase.tenant_ids_with(${q.key("read")}) x))
          or ((select realtime.topic()) like ${sqlString(`${q.topic}:%`)}
            and (select realtime.topic()) not like ${sqlString(`${q.topic}:org:%`)}
            and ${q.fn("inbox_conversation_allowed")}(substr((select realtime.topic()), ${String(q.topic.length + 2)})))
        )`;
  return `create or replace function ${q.fn("inbox_message_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new.${ms("conversation")}, 'message_id', new.${ms("id")}, 'kind', new.${ms("kind")});
  v_event text := case when tg_op = 'INSERT' then 'message' else 'message_updated' end;
begin
  if ${ready} then
    if new.${ms("kind")} = 'message' then
      ${send("v_payload", "v_event", topic.conversation(`new.${ms("conversation")}`))}
    end if;
    ${send("v_payload", "v_event", topic.org(`new.${ms("tenant")}`))}
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_message_broadcast")}() from public, anon, authenticated;
drop trigger if exists inbox_messages_broadcast on ${q.t("messages")};
create trigger inbox_messages_broadcast after insert or update on ${q.t("messages")}
  for each row execute function ${q.fn("inbox_message_broadcast")}();

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
    ${send("v_payload", "'conversation'", topic.conversation(`new.${cv("id")}`))}
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
      jsonb_build_object('conversation_id', m.${ms("conversation")}, 'message_id', new.${dl("message")}, 'status', new.${dl("status")}),
      'delivery',
      ${topic.org(`new.${dl("tenant")}`)},
      true
    )
    from ${q.t("messages")} m where m.${ms("id")} = new.${dl("message")};
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_delivery_broadcast")}() from public, anon, authenticated;
drop trigger if exists message_deliveries_broadcast on ${q.t("deliveries")};
create trigger message_deliveries_broadcast after insert or update of ${dl("status")} on ${q.t("deliveries")}
  for each row execute function ${q.fn("inbox_delivery_broadcast")}();

-- A contact's read reaches staff on the conversation topic, for read receipts.
create or replace function ${q.fn("inbox_read_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${ready} and exists (
    select 1 from ${q.t("conversations")} v join ${q.t("contacts")} c on c.${ct("id")} = v.${cv("contact")}
    where v.${cv("id")} = new.${rd("conversation")} and c.${ct("user")} = new.${rd("user")}
  ) then
    ${send(`jsonb_build_object('conversation_id', new.${rd("conversation")})`, "'read'", topic.conversation(`new.${rd("conversation")}`))}
  end if;
  return null;
end;
$$;
revoke execute on function ${q.fn("inbox_read_broadcast")}() from public, anon, authenticated;
drop trigger if exists conversation_reads_broadcast on ${q.t("reads")};
create trigger conversation_reads_broadcast after insert or update on ${q.t("reads")}
  for each row execute function ${q.fn("inbox_read_broadcast")}();

-- Staff join ${q.topic}:org:<tenant>; staff and the contact join
-- ${q.topic}:<conversation>, where they may also send typing broadcasts and
-- presence.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like ${sqlString(`${q.topic}:%`)}
        and ${allowed}
      );
    drop policy if exists ${broadcast} on realtime.messages;
    create policy ${broadcast} on realtime.messages for insert to authenticated
      with check (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like ${prefix} || '%'
        and (select realtime.topic()) not like ${org} || '%'
        and ${q.fn("inbox_conversation_allowed")}(substr((select realtime.topic()), ${String(q.topic.length + 2)}))
      );
  end if;
end;
$$;`;
}

/**
 * Files under `<tenant>/<conversation>/...` in the inbox bucket: staff of the
 * tenant and the conversation's contact read them; repliers upload.
 */
export function inboxStorage(q: InboxSql): string {
  const read = q.ctx.trigger("inbox_files_read");
  const write = q.ctx.trigger("inbox_files_write");
  const bucket = sqlString(q.bucket);
  const check = (writing: boolean): string =>
    `bucket_id = ${bucket} and ${q.fn("inbox_file_allowed")}(name, ${String(writing)})`;
  const cv = q.cols("conversations");
  return `create or replace function ${q.fn("inbox_file_allowed")}(object_name text, write boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select ${q.fn("inbox_conversation_allowed")}(v.${cv("id")}::text, write)
    from ${q.t("conversations")} v
    where v.${cv("tenant")}::text = split_part(object_name, '/', 1)
      and v.${cv("id")}::text = split_part(object_name, '/', 2)
  ), false);
$$;
revoke execute on function ${q.fn("inbox_file_allowed")}(text, boolean) from public, anon;
grant execute on function ${q.fn("inbox_file_allowed")}(text, boolean) to authenticated, service_role;

do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists ${read} on storage.objects;
    create policy ${read} on storage.objects for select to authenticated
      using (${check(false)});
    drop policy if exists ${write} on storage.objects;
    create policy ${write} on storage.objects for insert to authenticated
      with check (${check(true)});
  end if;
end;
$$;`;
}
