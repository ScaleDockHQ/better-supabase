-- better-supabase module: inbox (0.5.1)
-- @bs-module inbox@1 managed
-- Conversations with contacts across the in-app widget and chat channels: inboxes, members and teams, contacts with their channel identities, messages and internal notes, mentions, assignment, bot hand-off, read state, delivery status, stored webhook events and message templates. Staff read with inbox.read; contacts read their own conversations without the notes; Realtime pings carry ids only.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A shared inbox: conversations with contacts across the in-app widget and
-- the channels better-supabase/chat-sdk connects, internal notes, mentions,
-- assignment to members and teams, bot hand-off and delivery status. Staff
-- read through the inbox.read key; a signed-in contact reads their own
-- conversations without the notes. Writes go through the functions.
-- Inboxes: one per channel address (the in-app widget, a WhatsApp number, a
-- Slack workspace) in a tenant. bot_mode is the default for new
-- conversations: bot (the bot answers), human (staff answer) or paused.
create table if not exists "better_supabase"."inboxes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "channel" text not null default 'in_app' check ("channel" in ('in_app', 'email', 'slack', 'teams', 'discord', 'telegram', 'whatsapp', 'messenger', 'instagram', 'sms', 'github', 'linear', 'other')),
  "channel_address" text,
  "installation_id" uuid,
  "bot_mode" text not null default 'human' check ("bot_mode" in ('bot', 'human', 'paused')),
  "settings" jsonb not null default '{}'::jsonb check (jsonb_typeof("settings") = 'object'),
  "created_at" timestamptz not null default now(),
  "archived_at" timestamptz
);
create index if not exists inboxes_tenant_idx on "better_supabase"."inboxes" ("tenant_id");
create unique index if not exists inboxes_address_idx on "better_supabase"."inboxes" ("channel", "channel_address") where "channel_address" is not null and "archived_at" is null;
alter table "better_supabase"."inboxes" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bs_updated_at on "better_supabase"."inboxes";
create trigger bs_updated_at before update on "better_supabase"."inboxes"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inboxes" enable row level security;
revoke all on "better_supabase"."inboxes" from anon, authenticated;
grant select on "better_supabase"."inboxes" to authenticated;
grant all on "better_supabase"."inboxes" to service_role;
drop policy if exists inboxes_staff_read on "better_supabase"."inboxes";
create policy inboxes_staff_read on "better_supabase"."inboxes" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create table if not exists "better_supabase"."inbox_members" (
  "inbox_id" uuid not null references "better_supabase"."inboxes" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'agent' check ("role" in ('agent', 'lead')),
  "created_at" timestamptz not null default now(),
  primary key ("inbox_id", "user_id")
);
create index if not exists inbox_members_user_idx on "better_supabase"."inbox_members" ("user_id");
alter table "better_supabase"."inbox_members" enable row level security;
revoke all on "better_supabase"."inbox_members" from anon, authenticated;
grant select on "better_supabase"."inbox_members" to authenticated;
grant all on "better_supabase"."inbox_members" to service_role;
drop policy if exists inbox_members_staff_read on "better_supabase"."inbox_members";
create policy inbox_members_staff_read on "better_supabase"."inbox_members" for select to authenticated
  using (exists (select 1 from "better_supabase"."inboxes" i where i."id" = "inbox_id" and i."tenant_id" in (select better_supabase.tenant_ids_with('inbox.read'))));

create table if not exists "better_supabase"."inbox_teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "name")
);
alter table "better_supabase"."inbox_teams" enable row level security;
revoke all on "better_supabase"."inbox_teams" from anon, authenticated;
grant select on "better_supabase"."inbox_teams" to authenticated;
grant all on "better_supabase"."inbox_teams" to service_role;
drop policy if exists inbox_teams_staff_read on "better_supabase"."inbox_teams";
create policy inbox_teams_staff_read on "better_supabase"."inbox_teams" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create table if not exists "better_supabase"."inbox_team_members" (
  "team_id" uuid not null references "better_supabase"."inbox_teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index if not exists inbox_team_members_user_idx on "better_supabase"."inbox_team_members" ("user_id");
alter table "better_supabase"."inbox_team_members" enable row level security;
revoke all on "better_supabase"."inbox_team_members" from anon, authenticated;
grant select on "better_supabase"."inbox_team_members" to authenticated;
grant all on "better_supabase"."inbox_team_members" to service_role;
drop policy if exists inbox_team_members_staff_read on "better_supabase"."inbox_team_members";
create policy inbox_team_members_staff_read on "better_supabase"."inbox_team_members" for select to authenticated
  using (exists (select 1 from "better_supabase"."inbox_teams" t where t."id" = "team_id" and t."tenant_id" in (select better_supabase.tenant_ids_with('inbox.read'))));

-- The people staff talk to. user_id links a signed-in widget visitor (an
-- anonymous Auth user works too) to their contact.
create table if not exists "better_supabase"."contacts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text check (length("name") <= 200),
  "email" text check (length("email") <= 320),
  "phone" text check (length("phone") <= 50),
  "avatar_url" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
create unique index if not exists contacts_user_idx on "better_supabase"."contacts" ("tenant_id", "user_id") where "user_id" is not null;
create index if not exists contacts_email_idx on "better_supabase"."contacts" ("tenant_id", lower("email"));
create index if not exists contacts_user_id_idx on "better_supabase"."contacts" ("user_id");
alter table "better_supabase"."contacts" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bs_updated_at on "better_supabase"."contacts";
create trigger bs_updated_at before update on "better_supabase"."contacts"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."contacts" enable row level security;
revoke all on "better_supabase"."contacts" from anon, authenticated;
grant select on "better_supabase"."contacts" to authenticated;
grant all on "better_supabase"."contacts" to service_role;
drop policy if exists contacts_read on "better_supabase"."contacts";
create policy contacts_read on "better_supabase"."contacts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')) or "user_id" = (select auth.uid()));

-- A contact's address on a channel: a WhatsApp number, a Slack user id.
create table if not exists "better_supabase"."contact_identities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "contact_id" uuid not null references "better_supabase"."contacts" ("id") on delete cascade,
  "channel" text not null check (length("channel") between 1 and 50),
  "external_id" text not null check (length("external_id") between 1 and 500),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "channel", "external_id")
);
create index if not exists contact_identities_contact_idx on "better_supabase"."contact_identities" ("contact_id");
alter table "better_supabase"."contact_identities" enable row level security;
revoke all on "better_supabase"."contact_identities" from anon, authenticated;
grant select on "better_supabase"."contact_identities" to authenticated;
grant all on "better_supabase"."contact_identities" to service_role;
drop policy if exists contact_identities_staff_read on "better_supabase"."contact_identities";
create policy contact_identities_staff_read on "better_supabase"."contact_identities" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

-- One conversation per channel thread (thread_id is the Chat SDK thread id),
-- reopened when the contact writes again.
create table if not exists "better_supabase"."conversations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inbox_id" uuid not null references "better_supabase"."inboxes" ("id") on delete cascade,
  "contact_id" uuid not null references "better_supabase"."contacts" ("id") on delete cascade,
  "subject" text check (length("subject") <= 500),
  "status" text not null default 'open' check ("status" in ('open', 'pending', 'snoozed', 'resolved')),
  "priority" text not null default 'normal' check ("priority" in ('low', 'normal', 'high', 'urgent')),
  "assignee_id" uuid references auth.users (id) on delete set null,
  "team_id" uuid references "better_supabase"."inbox_teams" ("id") on delete set null,
  "bot_mode" text not null default 'human' check ("bot_mode" in ('bot', 'human', 'paused')),
  "thread_id" text,
  "snoozed_until" timestamptz,
  "last_message_at" timestamptz not null default now(),
  "last_message_preview" text,
  "first_response_at" timestamptz,
  "resolved_at" timestamptz,
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
create unique index if not exists conversations_thread_idx on "better_supabase"."conversations" ("inbox_id", "thread_id") where "thread_id" is not null;
create index if not exists conversations_list_idx on "better_supabase"."conversations" ("tenant_id", "status", "last_message_at" desc, "id");
create index if not exists conversations_assignee_idx on "better_supabase"."conversations" ("assignee_id") where "assignee_id" is not null;
create index if not exists conversations_contact_idx on "better_supabase"."conversations" ("contact_id");
create index if not exists conversations_inbox_idx on "better_supabase"."conversations" ("inbox_id");
create index if not exists conversations_team_idx on "better_supabase"."conversations" ("team_id") where "team_id" is not null;
alter table "better_supabase"."conversations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bs_updated_at on "better_supabase"."conversations";
create trigger bs_updated_at before update on "better_supabase"."conversations"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."conversations" enable row level security;
revoke all on "better_supabase"."conversations" from anon, authenticated;
grant select on "better_supabase"."conversations" to authenticated;
grant all on "better_supabase"."conversations" to service_role;

create table if not exists "better_supabase"."conversation_participants" (
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'participant' check ("role" in ('participant', 'watcher')),
  "created_at" timestamptz not null default now(),
  primary key ("conversation_id", "user_id")
);
create index if not exists conversation_participants_user_idx on "better_supabase"."conversation_participants" ("user_id");
alter table "better_supabase"."conversation_participants" enable row level security;
revoke all on "better_supabase"."conversation_participants" from anon, authenticated;
grant select on "better_supabase"."conversation_participants" to authenticated;
grant all on "better_supabase"."conversation_participants" to service_role;
drop policy if exists conversation_participants_staff_read on "better_supabase"."conversation_participants";
create policy conversation_participants_staff_read on "better_supabase"."conversation_participants" for select to authenticated
  using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id" and c."tenant_id" in (select better_supabase.tenant_ids_with('inbox.read'))));

-- The activity of a conversation: assignments, status and bot hand-offs.
create table if not exists "better_supabase"."conversation_events" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "actor_id" uuid references auth.users (id) on delete set null,
  "data" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default clock_timestamp()
);
create index if not exists conversation_events_conversation_idx on "better_supabase"."conversation_events" ("conversation_id", "id");
create index if not exists conversation_events_actor_idx on "better_supabase"."conversation_events" ("actor_id");
alter table "better_supabase"."conversation_events" enable row level security;
revoke all on "better_supabase"."conversation_events" from anon, authenticated;
grant select on "better_supabase"."conversation_events" to authenticated;
grant all on "better_supabase"."conversation_events" to service_role;
drop policy if exists conversation_events_staff_read on "better_supabase"."conversation_events";
create policy conversation_events_staff_read on "better_supabase"."conversation_events" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create table if not exists "better_supabase"."conversation_reads" (
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "last_read_at" timestamptz not null default now(),
  primary key ("conversation_id", "user_id")
);
create index if not exists conversation_reads_user_idx on "better_supabase"."conversation_reads" ("user_id");
alter table "better_supabase"."conversation_reads" enable row level security;
revoke all on "better_supabase"."conversation_reads" from anon, authenticated;
grant select on "better_supabase"."conversation_reads" to authenticated;
grant all on "better_supabase"."conversation_reads" to service_role;
drop policy if exists conversation_reads_own on "better_supabase"."conversation_reads";
create policy conversation_reads_own on "better_supabase"."conversation_reads" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Messages and internal notes. Contacts read the messages of their own
-- conversations, never the notes.
create table if not exists "better_supabase"."inbox_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "kind" text not null default 'message' check ("kind" in ('message', 'note')),
  "author_type" text not null check ("author_type" in ('contact', 'agent', 'bot', 'system')),
  "author_id" uuid references auth.users (id) on delete set null,
  "body" text not null default '' check (length("body") <= 20000),
  "format" text not null default 'text' check ("format" in ('text', 'markdown')),
  "attachments" jsonb not null default '[]'::jsonb check (jsonb_typeof("attachments") = 'array'),
  "reactions" jsonb not null default '{}'::jsonb check (jsonb_typeof("reactions") = 'object'),
  "mentions" uuid[] not null default '{}',
  "external_id" text,
  "reply_to" uuid references "better_supabase"."inbox_messages" ("id") on delete set null,
  "metadata" jsonb not null default '{}'::jsonb,
  -- clock_timestamp keeps a thread in order within one transaction.
  "created_at" timestamptz not null default clock_timestamp(),
  "edited_at" timestamptz,
  "deleted_at" timestamptz
);
create unique index if not exists inbox_messages_external_idx on "better_supabase"."inbox_messages" ("conversation_id", "external_id") where "external_id" is not null;
create index if not exists inbox_messages_conversation_idx on "better_supabase"."inbox_messages" ("conversation_id", "created_at", "id");
create index if not exists inbox_messages_author_idx on "better_supabase"."inbox_messages" ("author_id");
create index if not exists inbox_messages_reply_idx on "better_supabase"."inbox_messages" ("reply_to") where "reply_to" is not null;
alter table "better_supabase"."inbox_messages" enable row level security;
revoke all on "better_supabase"."inbox_messages" from anon, authenticated;
grant select on "better_supabase"."inbox_messages" to authenticated;
grant all on "better_supabase"."inbox_messages" to service_role;

-- What happened to an outbound message on its channel. Status only moves
-- forward: queued, sent, delivered, read; failed before delivery.
create table if not exists "better_supabase"."message_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."inbox_messages" ("id") on delete cascade,
  "channel" text not null,
  "status" text not null default 'queued' check ("status" in ('queued', 'sent', 'delivered', 'read', 'failed')),
  "external_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("message_id", "channel")
);
create index if not exists message_deliveries_external_idx on "better_supabase"."message_deliveries" ("channel", "external_id") where "external_id" is not null;
alter table "better_supabase"."message_deliveries" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bs_updated_at on "better_supabase"."message_deliveries";
create trigger bs_updated_at before update on "better_supabase"."message_deliveries"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."message_deliveries" enable row level security;
revoke all on "better_supabase"."message_deliveries" from anon, authenticated;
grant select on "better_supabase"."message_deliveries" to authenticated;
grant all on "better_supabase"."message_deliveries" to service_role;
drop policy if exists message_deliveries_staff_read on "better_supabase"."message_deliveries";
create policy message_deliveries_staff_read on "better_supabase"."message_deliveries" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create table if not exists "better_supabase"."inbox_mentions" (
  "message_id" uuid not null references "better_supabase"."inbox_messages" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "user_id")
);
create index if not exists inbox_mentions_user_idx on "better_supabase"."inbox_mentions" ("user_id", "created_at" desc);
alter table "better_supabase"."inbox_mentions" enable row level security;
revoke all on "better_supabase"."inbox_mentions" from anon, authenticated;
grant select on "better_supabase"."inbox_mentions" to authenticated;
grant all on "better_supabase"."inbox_mentions" to service_role;
drop policy if exists inbox_mentions_staff_read on "better_supabase"."inbox_mentions";
create policy inbox_mentions_staff_read on "better_supabase"."inbox_mentions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

-- Webhook deliveries from the channels, stored before the ack so a slow or
-- failed handler loses nothing. external_id dedupes a platform's retries.
create table if not exists "better_supabase"."inbound_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "adapter" text not null check (length("adapter") between 1 and 100),
  "external_id" text,
  "inbox_id" uuid references "better_supabase"."inboxes" ("id") on delete set null,
  "headers" jsonb not null default '{}'::jsonb,
  "body" text not null,
  "status" text not null default 'received' check ("status" in ('received', 'processed', 'ignored', 'failed')),
  "error" text,
  "attempts" integer not null default 0,
  "received_at" timestamptz not null default now(),
  "processed_at" timestamptz
);
create unique index if not exists inbound_events_external_idx on "better_supabase"."inbound_events" ("adapter", "external_id") where "external_id" is not null;
create index if not exists inbound_events_status_idx on "better_supabase"."inbound_events" ("status", "received_at");
create index if not exists inbound_events_inbox_idx on "better_supabase"."inbound_events" ("inbox_id");
alter table "better_supabase"."inbound_events" enable row level security;
revoke all on "better_supabase"."inbound_events" from anon, authenticated;
grant all on "better_supabase"."inbound_events" to service_role;

-- Approved templates for channels that need one outside a reply window
-- (WhatsApp after 24 hours). external_id is the platform's template name.
create table if not exists "better_supabase"."message_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inbox_id" uuid references "better_supabase"."inboxes" ("id") on delete cascade,
  "name" text not null check (length("name") between 1 and 200),
  "channel" text not null,
  "language" text not null default 'en',
  "body" text not null,
  "variables" jsonb not null default '[]'::jsonb check (jsonb_typeof("variables") = 'array'),
  "external_id" text,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "channel", "name", "language")
);
create index if not exists message_templates_inbox_idx on "better_supabase"."message_templates" ("inbox_id");
alter table "better_supabase"."message_templates" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bs_updated_at on "better_supabase"."message_templates";
create trigger bs_updated_at before update on "better_supabase"."message_templates"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."message_templates" enable row level security;
revoke all on "better_supabase"."message_templates" from anon, authenticated;
grant select on "better_supabase"."message_templates" to authenticated;
grant all on "better_supabase"."message_templates" to service_role;
drop policy if exists message_templates_staff_read on "better_supabase"."message_templates";
create policy message_templates_staff_read on "better_supabase"."message_templates" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create or replace function "better_supabase"."inbox_contact_ids"()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c."id" from "better_supabase"."contacts" c where c."user_id" = (select auth.uid());
$$;
revoke execute on function "better_supabase"."inbox_contact_ids"() from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_contact_ids"() to authenticated, service_role;

create or replace function "better_supabase"."inbox_contact_conversation_ids"()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id" from "better_supabase"."conversations" v
  join "better_supabase"."contacts" c on c."id" = v."contact_id"
  where c."user_id" = (select auth.uid());
$$;
revoke execute on function "better_supabase"."inbox_contact_conversation_ids"() from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_contact_conversation_ids"() to authenticated, service_role;

-- Whether the caller may see a conversation: staff of its tenant, or the
-- signed-in contact it belongs to. write asks for the reply key instead.
create or replace function "better_supabase"."inbox_conversation_allowed"(conversation text, write boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select (case when write then coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.reply'), false) else coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false) end)
      or exists (select 1 from "better_supabase"."contacts" c where c."id" = v."contact_id" and c."user_id" = (select auth.uid()))
    from "better_supabase"."conversations" v
    where v."id"::text = conversation
  ), false);
$$;
revoke execute on function "better_supabase"."inbox_conversation_allowed"(text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_conversation_allowed"(text, boolean) to authenticated, service_role;

drop policy if exists conversations_read on "better_supabase"."conversations";
create policy conversations_read on "better_supabase"."conversations" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')) or "contact_id" in (select "better_supabase"."inbox_contact_ids"()));
drop policy if exists inbox_messages_read on "better_supabase"."inbox_messages";
create policy inbox_messages_read on "better_supabase"."inbox_messages" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')) or ("kind" = 'message' and "conversation_id" in (select "better_supabase"."inbox_contact_conversation_ids"())));

-- When the contact last read the conversation, for staff read receipts.
create or replace function "better_supabase"."inbox_contact_read_at"(conversation uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select r."last_read_at"
  from "better_supabase"."conversations" v
  join "better_supabase"."contacts" c on c."id" = v."contact_id"
  join "better_supabase"."conversation_reads" r on r."conversation_id" = v."id" and r."user_id" = c."user_id"
  where v."id" = inbox_contact_read_at.conversation
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false));
$$;
revoke execute on function "better_supabase"."inbox_contact_read_at"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_contact_read_at"(uuid) to authenticated, service_role;

-- A conversation with its contact and inbox, as the reads return it.
create or replace function "better_supabase"."inbox_conversation_json"(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(v) || jsonb_build_object(
    'contact', (select jsonb_build_object('id', c."id", 'name', c."name", 'email', c."email", 'phone', c."phone", 'avatar_url', c."avatar_url", 'user_id', c."user_id") from "better_supabase"."contacts" c where c."id" = v."contact_id"),
    'inbox', (select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") from "better_supabase"."inboxes" i where i."id" = v."inbox_id"),
    'last_read_at', (select r."last_read_at" from "better_supabase"."conversation_reads" r where r."conversation_id" = v."id" and r."user_id" = (select auth.uid())),
    'contact_read_at', "better_supabase"."inbox_contact_read_at"(v."id")
  )
  from "better_supabase"."conversations" v
  where v."id" = conversation;
$$;
revoke execute on function "better_supabase"."inbox_conversation_json"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_conversation_json"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_inbox"(tenant uuid, name text, channel text default 'in_app', settings jsonb default '{}'::jsonb, bot_mode text default 'human', address text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inboxes" ("tenant_id", "name", "channel", "settings", "bot_mode", "channel_address")
  values (create_inbox.tenant, create_inbox.name, coalesce(create_inbox.channel, 'in_app'), coalesce(create_inbox.settings, '{}'::jsonb), coalesce(create_inbox.bot_mode, 'human'), create_inbox.address)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_inbox"(uuid, text, text, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."create_inbox"(uuid, text, text, jsonb, text, text) to authenticated, service_role;

-- patch keys: name, settings (merged), bot_mode, address, installation_id,
-- archived (true archives, false restores).
create or replace function "better_supabase"."update_inbox"(inbox uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  select * into v_row from "better_supabase"."inboxes" where "id" = update_inbox.inbox for update;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  update "better_supabase"."inboxes" set
    "name" = coalesce(patch ->> 'name', "name"),
    "settings" = "settings" || coalesce(patch -> 'settings', '{}'::jsonb),
    "bot_mode" = coalesce(patch ->> 'bot_mode', "bot_mode"),
    "channel_address" = case when patch ? 'address' then patch ->> 'address' else "channel_address" end,
    "installation_id" = case when patch ? 'installation_id' then (patch ->> 'installation_id')::uuid else "installation_id" end,
    "archived_at" = case when patch ? 'archived' then (case when (patch ->> 'archived')::boolean then coalesce("archived_at", now()) end) else "archived_at" end
  where "id" = update_inbox.inbox
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."update_inbox"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inbox"(uuid, jsonb) to authenticated, service_role;

-- Adds or updates a member; a null role removes them.
create or replace function "better_supabase"."set_inbox_member"(inbox uuid, member uuid, role text default 'agent')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."inboxes" where "id" = set_inbox_member.inbox;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if role is null then
    delete from "better_supabase"."inbox_members" m where m."inbox_id" = set_inbox_member.inbox and m."user_id" = member;
    return found;
  end if;
  if not coalesce(better_supabase.can_user(member, 'tenant', v_tenant, 'inbox.read'), false) then
    raise exception 'user cannot read this inbox' using errcode = '22023', hint = 'INBOX_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."inbox_members" ("inbox_id", "user_id", "role") values (set_inbox_member.inbox, member, role)
  on conflict ("inbox_id", "user_id") do update set "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_inbox_member"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_inbox_member"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."create_inbox_team"(tenant uuid, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inbox_teams"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox_team.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inbox_teams" ("tenant_id", "name") values (create_inbox_team.tenant, create_inbox_team.name)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_inbox_team"(uuid, text) from public, anon;
grant execute on function "better_supabase"."create_inbox_team"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."set_inbox_team_member"(team uuid, member uuid, present boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."inbox_teams" where "id" = set_inbox_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'INBOX_TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if not coalesce(present, true) then
    delete from "better_supabase"."inbox_team_members" t where t."team_id" = set_inbox_team_member.team and t."user_id" = member;
    return found;
  end if;
  insert into "better_supabase"."inbox_team_members" ("team_id", "user_id") values (set_inbox_team_member.team, member)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) to authenticated, service_role;

-- Finds or creates a contact: by id, then by the identity on a channel, the
-- signed-in user, then the email. Fields in input fill in what is missing;
-- an identity is attached when given. No permission check: callers check.
create or replace function "better_supabase"."inbox_resolve_contact"(tenant uuid, input jsonb)
returns "better_supabase"."contacts"
language plpgsql
set search_path = ''
as $$
declare
  v_contact "better_supabase"."contacts"%rowtype;
  v_identity jsonb := input -> 'identity';
begin
  if input ? 'id' then
    select * into v_contact from "better_supabase"."contacts" c where c."id" = (input ->> 'id')::uuid and c."tenant_id" = inbox_resolve_contact.tenant;
    if not found then
      raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
    end if;
  end if;
  if v_contact."id" is null and v_identity is not null then
    select c.* into v_contact from "better_supabase"."contact_identities" i join "better_supabase"."contacts" c on c."id" = i."contact_id"
    where i."tenant_id" = inbox_resolve_contact.tenant and i."channel" = v_identity ->> 'channel' and i."external_id" = v_identity ->> 'external_id';
  end if;
  if v_contact."id" is null and input ? 'user_id' then
    select * into v_contact from "better_supabase"."contacts" c where c."tenant_id" = inbox_resolve_contact.tenant and c."user_id" = (input ->> 'user_id')::uuid;
  end if;
  if v_contact."id" is null and nullif(input ->> 'email', '') is not null then
    select * into v_contact from "better_supabase"."contacts" c where c."tenant_id" = inbox_resolve_contact.tenant and lower(c."email") = lower(input ->> 'email')
    order by c."created_at" limit 1;
  end if;
  if v_contact."id" is null then
    insert into "better_supabase"."contacts" ("tenant_id", "user_id", "name", "email", "phone", "avatar_url", "metadata")
    values (inbox_resolve_contact.tenant, (input ->> 'user_id')::uuid, input ->> 'name', input ->> 'email', input ->> 'phone', input ->> 'avatar_url', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_contact;
  else
    update "better_supabase"."contacts" c set
      "name" = coalesce(c."name", input ->> 'name'),
      "email" = coalesce(c."email", input ->> 'email'),
      "phone" = coalesce(c."phone", input ->> 'phone'),
      "avatar_url" = coalesce(input ->> 'avatar_url', c."avatar_url"),
      "user_id" = coalesce(c."user_id", (input ->> 'user_id')::uuid),
      "metadata" = c."metadata" || coalesce(input -> 'metadata', '{}'::jsonb)
    where c."id" = v_contact."id"
    returning * into v_contact;
  end if;
  if v_identity is not null and v_identity ? 'channel' and v_identity ? 'external_id' then
    insert into "better_supabase"."contact_identities" ("tenant_id", "contact_id", "channel", "external_id")
    values (inbox_resolve_contact.tenant, v_contact."id", v_identity ->> 'channel', v_identity ->> 'external_id')
    on conflict do nothing;
  end if;
  return v_contact;
end;
$$;
revoke execute on function "better_supabase"."inbox_resolve_contact"(uuid, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."upsert_contact"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_contact.tenant, 'inbox.reply'), false)) then
    raise exception 'not allowed to edit contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  return to_jsonb("better_supabase"."inbox_resolve_contact"(upsert_contact.tenant, coalesce(input, '{}'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."upsert_contact"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_contact"(uuid, jsonb) to authenticated, service_role;

-- Stores a message on a conversation and moves the conversation along: the
-- preview, the first response, a reopen when the contact writes, mentions,
-- the bot job, the outbound job and the notifications. Callers check access.
create or replace function "better_supabase"."inbox_add_message"(conversation uuid, input jsonb, author_type text, author uuid, direction text)
returns "better_supabase"."inbox_messages"
language plpgsql
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_mentions uuid[];
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select * into v_msg from "better_supabase"."inbox_messages" m
    where m."conversation_id" = v_conv."id" and m."external_id" = input ->> 'external_id';
    if found then
      return v_msg;
    end if;
  end if;
  if length(btrim(coalesce(input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."inbox_messages" ("tenant_id", "conversation_id", "direction", "kind", "author_type", "author_id", "body", "format", "attachments", "mentions", "external_id", "reply_to", "metadata")
  values (
    v_conv."tenant_id", v_conv."id", inbox_add_message.direction, v_kind, inbox_add_message.author_type, inbox_add_message.author,
    coalesce(input ->> 'body', ''), coalesce(input ->> 'format', 'text'), coalesce(input -> 'attachments', '[]'::jsonb), v_mentions,
    input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_msg;
  insert into "better_supabase"."inbox_mentions" ("message_id", "user_id", "tenant_id")
  select v_msg."id", x, v_msg."tenant_id" from unnest(v_mentions) x
  on conflict do nothing;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."conversations" set
      "last_message_at" = v_msg."created_at",
      "last_message_preview" = left(v_msg."body", 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_msg."created_at"
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      
    end if;
  end if;
  if inbox_add_message.author is not null and inbox_add_message.author_type = 'agent' then
    insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_msg."id", 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_msg."tenant_id", v_msg."id", v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_msg."id", 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_msg."id"::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return v_msg;
end;
$$;
revoke execute on function "better_supabase"."inbox_add_message"(uuid, jsonb, text, uuid, text) from public, anon, authenticated;

-- Opens a conversation. Staff (the reply key) or the service name the
-- contact in input.contact (an id or the fields inbox_resolve_contact
-- takes); a signed-in visitor of an in-app inbox with settings.widget = true
-- opens one as themselves. input.message adds the first message.
create or replace function "better_supabase"."start_conversation"(inbox uuid, input jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."conversations"%rowtype;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false) then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), input ->> 'thread_id',
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_conv."thread_id" is null then
    update "better_supabase"."conversations" set "thread_id" = 'inbox:' || "id"::text
    where "id" = v_conv."id"
    returning * into v_conv;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."start_conversation"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."start_conversation"(uuid, jsonb) to authenticated, service_role;

-- Staff reply or add a note (input.kind = 'note'); the contact writes in
-- their own conversation; the service writes as the bot, the system, or the
-- contact (input.author_type). An agent's reply hands a bot conversation
-- over to staff.
create or replace function "better_supabase"."send_message"(conversation uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = send_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."contacts" c where c."id" = v_conv."contact_id" and c."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_msg := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  return to_jsonb(v_msg);
end;
$$;
revoke execute on function "better_supabase"."send_message"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_message"(uuid, jsonb) to authenticated, service_role;

-- A message that arrived on a channel, for the inbound handler: finds the
-- inbox's conversation for the thread (reopening it) or opens one, resolves
-- the contact by its identity on the channel, and stores the message once
-- per external_id. Returns { conversation_id, message_id, contact_id,
-- created, duplicate }.
create or replace function "better_supabase"."record_inbound"(input jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_message jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
    insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    v_created := true;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    
  end if;
  if v_message ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_messages" m where m."conversation_id" = v_conv."id" and m."external_id" = v_message ->> 'external_id');
  end if;
  v_msg := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_message - 'kind',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_msg."id",
    'contact_id', v_conv."contact_id",
    'tenant_id', v_conv."tenant_id",
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$$;
revoke execute on function "better_supabase"."record_inbound"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."record_inbound"(jsonb) to service_role;

-- Assigns a conversation to a member (null unassigns) and optionally a team.
-- The assign key assigns anyone; the reply key only takes it for oneself.
create or replace function "better_supabase"."assign_conversation"(conversation uuid, assignee uuid, team uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (assignee = (select auth.uid()) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  update "better_supabase"."conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    
    if assignee is not null then
      insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", assignee)
      on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."assign_conversation"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_conversation"(uuid, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_conversation_status"(conversation uuid, status text, snoozed_until timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and snoozed_until is null then
    raise exception 'snoozing needs snoozed_until' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  update "better_supabase"."conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from status then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      
    elsif v_before = 'resolved' then
      
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."set_conversation_status"(uuid, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."set_conversation_status"(uuid, text, timestamptz) to authenticated, service_role;

-- Sets who answers: bot, human (staff) or paused (nobody, e.g. while the
-- contact is blocked). Going from bot to human is a hand-off: the assignee
-- (or the inbox's members) are told.
create or replace function "better_supabase"."set_bot_mode"(conversation uuid, mode text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = set_bot_mode.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_before := v_conv."bot_mode";
  update "better_supabase"."conversations" set "bot_mode" = mode where "id" = v_conv."id" returning * into v_conv;
  if v_before is distinct from mode then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason));
    if v_before = 'bot' and mode = 'human' then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.handoff',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', coalesce(set_bot_mode.reason, v_conv."last_message_preview"),
        'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
        'key', 'inbox.handoff:' || v_conv."id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id", 'reason', set_bot_mode.reason)
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."set_bot_mode"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_bot_mode"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."mark_conversation_read"(conversation uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz := clock_timestamp();
begin
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."conversation_reads" ("conversation_id", "user_id", "last_read_at")
  values (conversation, (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = excluded."last_read_at";
  return v_at;
end;
$$;
revoke execute on function "better_supabase"."mark_conversation_read"(uuid) from public, anon;
grant execute on function "better_supabase"."mark_conversation_read"(uuid) to authenticated, service_role;

-- Adds or removes the caller's reaction; the service passes actor (a user
-- id, or a name such as the bot's). Returns the message's reactions.
create or replace function "better_supabase"."react_to_message"(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_who text;
begin
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = react_to_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_msg."conversation_id"::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  update "better_supabase"."inbox_messages" set "reactions" = case
    when coalesce(present, true) then
      "reactions" || jsonb_build_object(emoji, (
        select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
        from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb) || to_jsonb(v_who)) x
      ))
    else
      case when (select count(*) from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb)) x where x <> v_who) = 0
        then "reactions" - emoji
        else "reactions" || jsonb_build_object(emoji, (select jsonb_agg(x) from jsonb_array_elements_text("reactions" -> emoji) x where x <> v_who))
      end
    end
  where "id" = v_msg."id"
  returning * into v_msg;
  return v_msg."reactions";
end;
$$;
revoke execute on function "better_supabase"."react_to_message"(uuid, text, boolean, text) from public, anon;
grant execute on function "better_supabase"."react_to_message"(uuid, text, boolean, text) to authenticated, service_role;

-- The author (or the service) edits a message's body, or deletes it: the
-- row stays as a tombstone with an empty body.
create or replace function "better_supabase"."edit_message"(message uuid, body text default null, remove boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_msg "better_supabase"."inbox_messages"%rowtype;
begin
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = edit_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and v_msg."author_id" = (select auth.uid()))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."deleted_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  update "better_supabase"."inbox_messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_message.body, "body") end,
    "attachments" = case when coalesce(remove, false) then '[]'::jsonb else "attachments" end,
    "deleted_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id"
  returning * into v_msg;
  return to_jsonb(v_msg);
end;
$$;
revoke execute on function "better_supabase"."edit_message"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."edit_message"(uuid, text, boolean) to authenticated, service_role;

-- Conversations the caller reads (staff of the tenant, or a contact's own),
-- newest activity first. filter: inbox_id, status ('all' for every status),
-- assignee ('me', 'unassigned' or an id), team_id, contact_id, search,
-- before ({ last_message_at, id } of the previous page's last item), limit.
create or replace function "better_supabase"."list_conversations"(tenant uuid default null, filter jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg("better_supabase"."inbox_conversation_json"(page."id") || jsonb_build_object('unread', page.unread) order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
  from (
    select v."id", v."last_message_at",
      v."last_message_at" > coalesce((select r."last_read_at" from "better_supabase"."conversation_reads" r where r."conversation_id" = v."id" and r."user_id" = (select auth.uid())), '-infinity'::timestamptz) as unread
    from "better_supabase"."conversations" v
    left join "better_supabase"."contacts" c on c."id" = v."contact_id"
    where (list_conversations.tenant is null or v."tenant_id" = list_conversations.tenant)
      and (filter ->> 'inbox_id' is null or v."inbox_id" = (filter ->> 'inbox_id')::uuid)
      and (coalesce(filter ->> 'status', 'open') = 'all' or v."status" = coalesce(filter ->> 'status', 'open'))
      and (case filter ->> 'assignee'
        when 'me' then v."assignee_id" = (select auth.uid())
        when 'unassigned' then v."assignee_id" is null
        else filter ->> 'assignee' is null or v."assignee_id" = (filter ->> 'assignee')::uuid end)
      and (filter ->> 'team_id' is null or v."team_id" = (filter ->> 'team_id')::uuid)
      and (filter ->> 'contact_id' is null or v."contact_id" = (filter ->> 'contact_id')::uuid)
      and (nullif(filter ->> 'search', '') is null
        or v."subject" ilike '%' || (filter ->> 'search') || '%'
        or v."last_message_preview" ilike '%' || (filter ->> 'search') || '%'
        or c."name" ilike '%' || (filter ->> 'search') || '%'
        or c."email" ilike '%' || (filter ->> 'search') || '%')
      and (filter -> 'before' is null
        or (v."last_message_at", v."id") < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
    order by v."last_message_at" desc, v."id" desc
    limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
  ) page;
$$;
revoke execute on function "better_supabase"."list_conversations"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_conversations"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_conversation"(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."inbox_conversation_json"(v."id") from "better_supabase"."conversations" v where v."id" = conversation;
$$;
revoke execute on function "better_supabase"."get_conversation"(uuid) from public, anon;
grant execute on function "better_supabase"."get_conversation"(uuid) to authenticated, service_role;

-- A page of messages, oldest first, ending before the given instant. Staff
-- also get notes and each outbound message's delivery.
create or replace function "better_supabase"."list_messages"(conversation uuid, before timestamptz default null, max integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(page.item order by page.created_at, page.id), '[]'::jsonb)
  from (
    select m."created_at" as created_at, m."id" as id,
      to_jsonb(m) || jsonb_build_object('delivery', (
        select jsonb_build_object('status', d."status", 'channel', d."channel", 'error', d."error", 'updated_at', d."updated_at")
        from "better_supabase"."message_deliveries" d where d."message_id" = m."id"
        order by d."created_at" limit 1
      )) as item
    from "better_supabase"."inbox_messages" m
    where m."conversation_id" = list_messages.conversation
      and (before is null or m."created_at" < before)
    order by m."created_at" desc, m."id" desc
    limit least(greatest(coalesce(max, 50), 1), 200)
  ) page;
$$;
revoke execute on function "better_supabase"."list_messages"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_messages"(uuid, timestamptz, integer) to authenticated, service_role;

-- The conversation's activity log, for staff.
create or replace function "better_supabase"."list_conversation_events"(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."id"), '[]'::jsonb)
  from "better_supabase"."conversation_events" e where e."conversation_id" = list_conversation_events.conversation;
$$;
revoke execute on function "better_supabase"."list_conversation_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_conversation_events"(uuid) to authenticated, service_role;

-- Counts of open conversations for the caller: all, assigned to them,
-- unassigned, and those with activity since they last read them.
create or replace function "better_supabase"."inbox_counts"(tenant uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'open', count(*),
    'mine', count(*) filter (where v."assignee_id" = (select auth.uid())),
    'unassigned', count(*) filter (where v."assignee_id" is null),
    'unread', count(*) filter (where v."last_message_at" > coalesce(r."last_read_at", '-infinity'::timestamptz)
      and (v."assignee_id" is null or v."assignee_id" = (select auth.uid())))
  )
  from "better_supabase"."conversations" v
  left join "better_supabase"."conversation_reads" r on r."conversation_id" = v."id" and r."user_id" = (select auth.uid())
  where v."tenant_id" = inbox_counts.tenant and v."status" = 'open';
$$;
revoke execute on function "better_supabase"."inbox_counts"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_counts"(uuid) to authenticated, service_role;

-- One message with its first delivery, under the caller's RLS.
create or replace function "better_supabase"."get_message"(message uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(m) || jsonb_build_object('delivery', (
    select jsonb_build_object('status', d."status", 'channel', d."channel", 'error', d."error", 'updated_at', d."updated_at")
    from "better_supabase"."message_deliveries" d where d."message_id" = m."id"
    order by d."created_at" limit 1
  ))
  from "better_supabase"."inbox_messages" m where m."id" = get_message.message;
$$;
revoke execute on function "better_supabase"."get_message"(uuid) from public, anon;
grant execute on function "better_supabase"."get_message"(uuid) to authenticated, service_role;

-- A typing ping on the conversation's topic, from staff, the contact or
-- the service (actor names the bot).
create or replace function "better_supabase"."set_typing"(conversation uuid, typing boolean default true, actor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_who text;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(actor, 'bot');
  elsif "better_supabase"."inbox_conversation_allowed"(conversation::text, true) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  perform realtime.send(
    jsonb_build_object('user_id', v_who, 'typing', coalesce(typing, true)),
    'typing',
    'inbox:' || conversation::text,
    true
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_typing"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."set_typing"(uuid, boolean, text) to authenticated, service_role;

-- After posting an outbound message on its channel: records the platform's
-- id and the status.
create or replace function "better_supabase"."record_delivery"(message uuid, channel text, external_id text default null, status text default 'sent', error text default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."message_deliveries"%rowtype;
begin
  insert into "better_supabase"."message_deliveries" as d ("tenant_id", "message_id", "channel", "external_id", "status", "error", "attempts")
  select m."tenant_id", m."id", record_delivery.channel, record_delivery.external_id, coalesce(record_delivery.status, 'sent'), record_delivery.error, 1
  from "better_supabase"."inbox_messages" m where m."id" = record_delivery.message
  on conflict ("message_id", "channel") do update set
    "external_id" = coalesce(excluded."external_id", d."external_id"),
    "status" = excluded."status",
    "error" = excluded."error",
    "attempts" = d."attempts" + 1
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."record_delivery"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_delivery"(uuid, text, text, text, text) to service_role;

-- A status callback from the channel. Status only moves forward (queued,
-- sent, delivered, read); failed counts only before delivery. Returns the
-- number of deliveries changed.
create or replace function "better_supabase"."set_delivery_status"(channel text, external_id text, status text, error text default null)
returns integer
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_count integer;
begin
  update "better_supabase"."message_deliveries" d set "status" = status, "error" = coalesce(error, d."error")
  where d."channel" = channel and d."external_id" = external_id
    and (case status when 'failed' then d."status" in ('queued', 'sent')
      else array_position(array['queued', 'sent', 'delivered', 'read'], status)
        > coalesce(array_position(array['queued', 'sent', 'delivered', 'read'], d."status"), 0) end);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_delivery_status"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_delivery_status"(text, text, text, text) to service_role;

-- Stores a webhook body before the ack. { id, duplicate }: a duplicate is a
-- retry of an event already stored under the same external_id.
create or replace function "better_supabase"."store_inbound_event"(adapter text, body text, external_id text default null, headers jsonb default '{}'::jsonb, inbox uuid default null, tenant uuid default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into "better_supabase"."inbound_events" ("adapter", "body", "external_id", "headers", "inbox_id", "tenant_id")
  values (adapter, body, external_id, coalesce(headers, '{}'::jsonb), inbox, tenant)
  on conflict do nothing
  returning "id" into v_id;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'duplicate', false);
  end if;
  select e."id" into v_id from "better_supabase"."inbound_events" e where e."adapter" = adapter and e."external_id" = external_id;
  return jsonb_build_object('id', v_id, 'duplicate', true);
end;
$$;
revoke execute on function "better_supabase"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) to service_role;

create or replace function "better_supabase"."set_inbound_event_status"(event uuid, status text, error text default null)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "better_supabase"."inbound_events" e set
    "status" = status,
    "error" = error,
    "attempts" = e."attempts" + 1,
    "processed_at" = case when status in ('processed', 'ignored') then now() else e."processed_at" end
  where e."id" = event;
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_inbound_event_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_inbound_event_status"(uuid, text, text) to service_role;

-- Inbound events still waiting, oldest first, for a retry sweep.
create or replace function "better_supabase"."pending_inbound_events"(max integer default 100, max_attempts integer default 5)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."received_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."inbound_events" x
    where x."status" in ('received', 'failed') and x."attempts" < coalesce(max_attempts, 5)
    order by x."received_at"
    limit least(greatest(coalesce(max, 100), 1), 1000)
  ) e;
$$;
revoke execute on function "better_supabase"."pending_inbound_events"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_inbound_events"(integer, integer) to service_role;

-- Deletes handled inbound events older than older_than, at most batch.
create or replace function "better_supabase"."purge_inbound_events"(older_than interval default '30 days', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."inbound_events" e where e."id" in (
    select x."id" from "better_supabase"."inbound_events" x
    where x."received_at" < now() - coalesce(older_than, interval '30 days')
      and x."status" in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_inbound_events"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_inbound_events"(interval, integer) to service_role;

-- Reopens snoozed conversations whose time came, for a periodic job.
create or replace function "better_supabase"."wake_snoozed_conversations"()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  update "better_supabase"."conversations" set "status" = 'open', "snoozed_until" = null
  where "status" = 'snoozed' and "snoozed_until" <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."wake_snoozed_conversations"() from public, anon, authenticated;
grant execute on function "better_supabase"."wake_snoozed_conversations"() to service_role;

create or replace function "better_supabase"."upsert_message_template"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."message_templates"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."message_templates" as t ("tenant_id", "inbox_id", "name", "channel", "language", "body", "variables", "external_id")
  values (tenant, (input ->> 'inbox_id')::uuid, input ->> 'name', input ->> 'channel', coalesce(input ->> 'language', 'en'), input ->> 'body', coalesce(input -> 'variables', '[]'::jsonb), input ->> 'external_id')
  on conflict ("tenant_id", "channel", "name", "language") do update set
    "inbox_id" = excluded."inbox_id",
    "body" = excluded."body",
    "variables" = excluded."variables",
    "external_id" = excluded."external_id"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."upsert_message_template"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_message_template"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_message_template"(template uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."message_templates" where "id" = delete_message_template.template;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  delete from "better_supabase"."message_templates" t where t."id" = delete_message_template.template;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_message_template"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_message_template"(uuid) to authenticated, service_role;

-- Erases a contact for a data subject request: the contact, its identities
-- and its conversations with their messages, deliveries and events. Returns
-- { conversations, messages, attachments }; attachments are the storage
-- paths the caller still has to remove.
create or replace function "better_supabase"."purge_contact"(contact uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_conversations integer;
  v_messages integer;
  v_paths jsonb;
begin
  select c."tenant_id" into v_tenant from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select count(*)::integer into v_conversations from "better_supabase"."conversations" v where v."contact_id" = purge_contact.contact;
  select coalesce(jsonb_agg(a ->> 'path') filter (where a ? 'path'), '[]'::jsonb)
  into v_paths
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  left join lateral jsonb_array_elements(m."attachments") a on true
  where v."contact_id" = purge_contact.contact;
  select count(*)::integer into v_messages
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  where v."contact_id" = purge_contact.contact;
  delete from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  return jsonb_build_object('conversations', v_conversations, 'messages', v_messages, 'attachments', v_paths);
end;
$$;
revoke execute on function "better_supabase"."purge_contact"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_contact"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."inbox_message_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new."conversation_id", 'message_id', new."id", 'kind', new."kind");
  v_event text := case when tg_op = 'INSERT' then 'message' else 'message_updated' end;
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    if new."kind" = 'message' then
      perform realtime.send(v_payload, v_event, 'inbox:' || new."conversation_id"::text, true);
    end if;
    perform realtime.send(v_payload, v_event, 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_message_broadcast"() from public, anon, authenticated;
drop trigger if exists inbox_messages_broadcast on "better_supabase"."inbox_messages";
create trigger inbox_messages_broadcast after insert or update on "better_supabase"."inbox_messages"
  for each row execute function "better_supabase"."inbox_message_broadcast"();

create or replace function "better_supabase"."inbox_conversation_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new."id");
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(v_payload, 'conversation', 'inbox:' || new."id"::text, true);
    perform realtime.send(v_payload, 'conversation', 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_conversation_broadcast"() from public, anon, authenticated;
drop trigger if exists conversations_broadcast on "better_supabase"."conversations";
create trigger conversations_broadcast after insert or update on "better_supabase"."conversations"
  for each row execute function "better_supabase"."inbox_conversation_broadcast"();

create or replace function "better_supabase"."inbox_delivery_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversation_id', m."conversation_id", 'message_id', new."message_id", 'status', new."status"),
      'delivery',
      'inbox:org:' || new."tenant_id"::text,
      true
    )
    from "better_supabase"."inbox_messages" m where m."id" = new."message_id";
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_delivery_broadcast"() from public, anon, authenticated;
drop trigger if exists message_deliveries_broadcast on "better_supabase"."message_deliveries";
create trigger message_deliveries_broadcast after insert or update of "status" on "better_supabase"."message_deliveries"
  for each row execute function "better_supabase"."inbox_delivery_broadcast"();

-- A contact's read reaches staff on the conversation topic, for read receipts.
create or replace function "better_supabase"."inbox_read_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and exists (
    select 1 from "better_supabase"."conversations" v join "better_supabase"."contacts" c on c."id" = v."contact_id"
    where v."id" = new."conversation_id" and c."user_id" = new."user_id"
  ) then
    perform realtime.send(jsonb_build_object('conversation_id', new."conversation_id"), 'read', 'inbox:' || new."conversation_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_read_broadcast"() from public, anon, authenticated;
drop trigger if exists conversation_reads_broadcast on "better_supabase"."conversation_reads";
create trigger conversation_reads_broadcast after insert or update on "better_supabase"."conversation_reads"
  for each row execute function "better_supabase"."inbox_read_broadcast"();

-- Staff join inbox:org:<tenant>; staff and the contact join
-- inbox:<conversation>, where they may also send typing broadcasts and
-- presence.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_inbox_receive" on realtime.messages;
    create policy "bs_inbox_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'inbox:%'
        and (
          ((select realtime.topic()) like 'inbox:org:%'
            and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('inbox.read') x))
          or ((select realtime.topic()) like 'inbox:%'
            and (select realtime.topic()) not like 'inbox:org:%'
            and "better_supabase"."inbox_conversation_allowed"(substr((select realtime.topic()), 7)))
        )
      );
    drop policy if exists "bs_inbox_broadcast" on realtime.messages;
    create policy "bs_inbox_broadcast" on realtime.messages for insert to authenticated
      with check (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'inbox:' || '%'
        and (select realtime.topic()) not like 'inbox:org:' || '%'
        and "better_supabase"."inbox_conversation_allowed"(substr((select realtime.topic()), 7))
      );
  end if;
end;
$$;

create or replace function "better_supabase"."inbox_file_allowed"(object_name text, write boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select "better_supabase"."inbox_conversation_allowed"(v."id"::text, write)
    from "better_supabase"."conversations" v
    where v."tenant_id"::text = split_part(object_name, '/', 1)
      and v."id"::text = split_part(object_name, '/', 2)
  ), false);
$$;
revoke execute on function "better_supabase"."inbox_file_allowed"(text, boolean) from public, anon;
grant execute on function "better_supabase"."inbox_file_allowed"(text, boolean) to authenticated, service_role;

do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "bs_inbox_files_read" on storage.objects;
    create policy "bs_inbox_files_read" on storage.objects for select to authenticated
      using (bucket_id = 'inbox-files' and "better_supabase"."inbox_file_allowed"(name, false));
    drop policy if exists "bs_inbox_files_write" on storage.objects;
    create policy "bs_inbox_files_write" on storage.objects for insert to authenticated
      with check (bucket_id = 'inbox-files' and "better_supabase"."inbox_file_allowed"(name, true));
  end if;
end;
$$;

-- sql.modules.inbox.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."inbox_contact_ids"();
drop function if exists "api"."inbox_contact_conversation_ids"();
drop function if exists "api"."inbox_conversation_allowed"(text, boolean);
drop function if exists "api"."inbox_conversation_json"(uuid);
drop function if exists "api"."inbox_file_allowed"(text, boolean);

create or replace function "api"."inbox_contact_read_at"(conversation uuid)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inbox_contact_read_at"($1) $$;
revoke execute on function "api"."inbox_contact_read_at"(uuid) from public, anon;
grant execute on function "api"."inbox_contact_read_at"(uuid) to authenticated, service_role;

create or replace function "api"."create_inbox"(tenant uuid, name text, channel text default 'in_app', settings jsonb default '{}'::jsonb, bot_mode text default 'human', address text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_inbox"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_inbox"(uuid, text, text, jsonb, text, text) from public, anon;
grant execute on function "api"."create_inbox"(uuid, text, text, jsonb, text, text) to authenticated, service_role;

create or replace function "api"."update_inbox"(inbox uuid, patch jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_inbox"($1, $2) $$;
revoke execute on function "api"."update_inbox"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_inbox"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_inbox_member"(inbox uuid, member uuid, role text default 'agent')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_inbox_member"($1, $2, $3) $$;
revoke execute on function "api"."set_inbox_member"(uuid, uuid, text) from public, anon;
grant execute on function "api"."set_inbox_member"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."create_inbox_team"(tenant uuid, name text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_inbox_team"($1, $2) $$;
revoke execute on function "api"."create_inbox_team"(uuid, text) from public, anon;
grant execute on function "api"."create_inbox_team"(uuid, text) to authenticated, service_role;

create or replace function "api"."set_inbox_team_member"(team uuid, member uuid, present boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_inbox_team_member"($1, $2, $3) $$;
revoke execute on function "api"."set_inbox_team_member"(uuid, uuid, boolean) from public, anon;
grant execute on function "api"."set_inbox_team_member"(uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."upsert_contact"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_contact"($1, $2) $$;
revoke execute on function "api"."upsert_contact"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_contact"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."start_conversation"(inbox uuid, input jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_conversation"($1, $2) $$;
revoke execute on function "api"."start_conversation"(uuid, jsonb) from public, anon;
grant execute on function "api"."start_conversation"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."send_message"(conversation uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_message"($1, $2) $$;
revoke execute on function "api"."send_message"(uuid, jsonb) from public, anon;
grant execute on function "api"."send_message"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."record_inbound"(input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_inbound"($1) $$;
revoke execute on function "api"."record_inbound"(jsonb) from public, anon, authenticated;
grant execute on function "api"."record_inbound"(jsonb) to service_role;

create or replace function "api"."assign_conversation"(conversation uuid, assignee uuid, team uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_conversation"($1, $2, $3) $$;
revoke execute on function "api"."assign_conversation"(uuid, uuid, uuid) from public, anon;
grant execute on function "api"."assign_conversation"(uuid, uuid, uuid) to authenticated, service_role;

create or replace function "api"."set_conversation_status"(conversation uuid, status text, snoozed_until timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_conversation_status"($1, $2, $3) $$;
revoke execute on function "api"."set_conversation_status"(uuid, text, timestamptz) from public, anon;
grant execute on function "api"."set_conversation_status"(uuid, text, timestamptz) to authenticated, service_role;

create or replace function "api"."set_bot_mode"(conversation uuid, mode text, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_bot_mode"($1, $2, $3) $$;
revoke execute on function "api"."set_bot_mode"(uuid, text, text) from public, anon;
grant execute on function "api"."set_bot_mode"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."mark_conversation_read"(conversation uuid)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_conversation_read"($1) $$;
revoke execute on function "api"."mark_conversation_read"(uuid) from public, anon;
grant execute on function "api"."mark_conversation_read"(uuid) to authenticated, service_role;

create or replace function "api"."react_to_message"(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."react_to_message"($1, $2, $3, $4) $$;
revoke execute on function "api"."react_to_message"(uuid, text, boolean, text) from public, anon;
grant execute on function "api"."react_to_message"(uuid, text, boolean, text) to authenticated, service_role;

create or replace function "api"."edit_message"(message uuid, body text default null, remove boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."edit_message"($1, $2, $3) $$;
revoke execute on function "api"."edit_message"(uuid, text, boolean) from public, anon;
grant execute on function "api"."edit_message"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."list_conversations"(tenant uuid default null, filter jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_conversations"($1, $2) $$;
revoke execute on function "api"."list_conversations"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_conversations"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_conversation"(conversation uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_conversation"($1) $$;
revoke execute on function "api"."get_conversation"(uuid) from public, anon;
grant execute on function "api"."get_conversation"(uuid) to authenticated, service_role;

create or replace function "api"."list_messages"(conversation uuid, before timestamptz default null, max integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_messages"($1, $2, $3) $$;
revoke execute on function "api"."list_messages"(uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."list_messages"(uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."list_conversation_events"(conversation uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_conversation_events"($1) $$;
revoke execute on function "api"."list_conversation_events"(uuid) from public, anon;
grant execute on function "api"."list_conversation_events"(uuid) to authenticated, service_role;

create or replace function "api"."inbox_counts"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inbox_counts"($1) $$;
revoke execute on function "api"."inbox_counts"(uuid) from public, anon;
grant execute on function "api"."inbox_counts"(uuid) to authenticated, service_role;

create or replace function "api"."get_message"(message uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_message"($1) $$;
revoke execute on function "api"."get_message"(uuid) from public, anon;
grant execute on function "api"."get_message"(uuid) to authenticated, service_role;

create or replace function "api"."set_typing"(conversation uuid, typing boolean default true, actor text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_typing"($1, $2, $3) $$;
revoke execute on function "api"."set_typing"(uuid, boolean, text) from public, anon;
grant execute on function "api"."set_typing"(uuid, boolean, text) to authenticated, service_role;

create or replace function "api"."record_delivery"(message uuid, channel text, external_id text default null, status text default 'sent', error text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_delivery"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_delivery"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."record_delivery"(uuid, text, text, text, text) to service_role;

create or replace function "api"."set_delivery_status"(channel text, external_id text, status text, error text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_delivery_status"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_delivery_status"(text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."set_delivery_status"(text, text, text, text) to service_role;

create or replace function "api"."store_inbound_event"(adapter text, body text, external_id text default null, headers jsonb default '{}'::jsonb, inbox uuid default null, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."store_inbound_event"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) to service_role;

create or replace function "api"."set_inbound_event_status"(event uuid, status text, error text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_inbound_event_status"($1, $2, $3) $$;
revoke execute on function "api"."set_inbound_event_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."set_inbound_event_status"(uuid, text, text) to service_role;

create or replace function "api"."pending_inbound_events"(max integer default 100, max_attempts integer default 5)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_inbound_events"($1, $2) $$;
revoke execute on function "api"."pending_inbound_events"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."pending_inbound_events"(integer, integer) to service_role;

create or replace function "api"."purge_inbound_events"(older_than interval default '30 days', batch integer default 1000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_inbound_events"($1, $2) $$;
revoke execute on function "api"."purge_inbound_events"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_inbound_events"(interval, integer) to service_role;

create or replace function "api"."wake_snoozed_conversations"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."wake_snoozed_conversations"() $$;
revoke execute on function "api"."wake_snoozed_conversations"() from public, anon, authenticated;
grant execute on function "api"."wake_snoozed_conversations"() to service_role;

create or replace function "api"."upsert_message_template"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_message_template"($1, $2) $$;
revoke execute on function "api"."upsert_message_template"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_message_template"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_message_template"(template uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_message_template"($1) $$;
revoke execute on function "api"."delete_message_template"(uuid) from public, anon;
grant execute on function "api"."delete_message_template"(uuid) to authenticated, service_role;

create or replace function "api"."purge_contact"(contact uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_contact"($1) $$;
revoke execute on function "api"."purge_contact"(uuid) from public, anon;
grant execute on function "api"."purge_contact"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
