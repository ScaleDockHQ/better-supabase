-- better-supabase module: inbox
-- @bsb-block inbox@8 managed
-- @bsb-hash sha256:97e108bfbe2788212f47a70cf092d1d208384241ca0ceaa89234aab2afb86136
-- Conversations with contacts across the in-app widget and chat channels, on the messaging core: inboxes, members and teams, contacts who are people of the contacts block, messages and internal notes with scanned files, mentions, assignment, bot hand-off, read state, delivery status, stored webhook events, message templates, scheduled replies and reply drafts, including ai drafts staff review. Staff read with inbox.read; contacts read their own conversations without the notes; Realtime pings carry ids only.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inboxes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inboxes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inboxes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inboxes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inboxes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_conversations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_conversations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_conversations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_conversations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_conversations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_conversation_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_conversation_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_conversation_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_conversation_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_conversation_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_details";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_details";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_details";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_details";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_details";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_inbound_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_inbound_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_inbound_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_inbound_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_inbound_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."scheduled_inbox_messages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."scheduled_inbox_messages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."scheduled_inbox_messages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."scheduled_inbox_messages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."scheduled_inbox_messages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_drafts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_drafts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_drafts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_drafts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_drafts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A shared inbox on the messaging core: each conversation with a contact is
-- a core conversation of kind inbox, each message (or internal note) a core
-- message with its inbox fields in inbox_message_details, and files are
-- attachments. Across the in-app widget and the channels
-- better-supabase/chat-sdk connects, with assignment to members and teams,
-- bot hand-off and delivery status. Staff read through the inbox.read key; a
-- signed-in contact reads their own conversations without the notes. Writes
-- go through the functions.
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
drop trigger if exists bsb_updated_at on "better_supabase"."inboxes";
create trigger bsb_updated_at before update on "better_supabase"."inboxes"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inboxes" enable row level security;
revoke all on "better_supabase"."inboxes" from public, anon, authenticated;
grant select on "better_supabase"."inboxes" to authenticated;
grant all on "better_supabase"."inboxes" to service_role;
drop policy if exists inboxes_staff_read on "better_supabase"."inboxes";
create policy inboxes_staff_read on "better_supabase"."inboxes"
  for select to authenticated
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
revoke all on "better_supabase"."inbox_members" from public, anon, authenticated;
grant select on "better_supabase"."inbox_members" to authenticated;
grant all on "better_supabase"."inbox_members" to service_role;
drop policy if exists inbox_members_staff_read on "better_supabase"."inbox_members";
create policy inbox_members_staff_read on "better_supabase"."inbox_members"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."inboxes" i where i."id" = "inbox_id" and i."tenant_id" in (select better_supabase.tenant_ids_with('inbox.read'))));

-- Teams live in the teams module. Assignment stores that module's id.

-- The inbox side of a core conversation of kind inbox, with the same id:
-- one per channel thread (thread_id is the Chat SDK thread id), reopened
-- when the contact writes again. last_message_at and the preview follow the
-- messages, never the notes. contact_id is a person of the contacts block,
-- which adds its foreign key: contacts renders after the inbox.
create table if not exists "better_supabase"."inbox_conversations" (
  "id" uuid primary key,
  "tenant_id" uuid not null,
  "inbox_id" uuid not null references "better_supabase"."inboxes" ("id") on delete cascade,
  "contact_id" uuid not null,
  "subject" text check (length("subject") <= 500),
  "status" text not null default 'open' check ("status" in ('open', 'pending', 'snoozed', 'resolved')),
  "priority" text not null default 'normal' check ("priority" in ('low', 'normal', 'high', 'urgent')),
  "assignee_id" uuid references auth.users (id) on delete set null,
  "team_id" uuid,
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
create unique index if not exists conversations_thread_idx on "better_supabase"."inbox_conversations" ("inbox_id", "thread_id") where "thread_id" is not null;
create index if not exists conversations_list_idx on "better_supabase"."inbox_conversations" ("tenant_id", "status", "last_message_at" desc, "id");
create index if not exists conversations_assignee_idx on "better_supabase"."inbox_conversations" ("assignee_id") where "assignee_id" is not null;
create index if not exists conversations_contact_idx on "better_supabase"."inbox_conversations" ("contact_id");
create index if not exists conversations_inbox_idx on "better_supabase"."inbox_conversations" ("inbox_id");
create index if not exists conversations_team_idx on "better_supabase"."inbox_conversations" ("team_id") where "team_id" is not null;
alter table "better_supabase"."inbox_conversations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."inbox_conversations";
create trigger bsb_updated_at before update on "better_supabase"."inbox_conversations"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inbox_conversations" enable row level security;
revoke all on "better_supabase"."inbox_conversations" from public, anon, authenticated;
grant select on "better_supabase"."inbox_conversations" to authenticated;
grant all on "better_supabase"."inbox_conversations" to service_role;

-- The activity of a conversation: assignments, status and bot hand-offs.
create table if not exists "better_supabase"."inbox_conversation_events" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."inbox_conversations" ("id") on delete cascade,
  "type" text not null check ("type" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "actor_id" uuid references auth.users (id) on delete set null,
  "data" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default clock_timestamp()
);
create index if not exists "inbox_conversation_events_conversation_idx" on "better_supabase"."inbox_conversation_events" ("conversation_id", "id");
create index if not exists "inbox_conversation_events_actor_idx" on "better_supabase"."inbox_conversation_events" ("actor_id");
alter table "better_supabase"."inbox_conversation_events" enable row level security;
revoke all on "better_supabase"."inbox_conversation_events" from public, anon, authenticated;
grant select on "better_supabase"."inbox_conversation_events" to authenticated;
grant all on "better_supabase"."inbox_conversation_events" to service_role;
drop policy if exists inbox_conversation_events_staff_read on "better_supabase"."inbox_conversation_events";
create policy inbox_conversation_events_staff_read on "better_supabase"."inbox_conversation_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

create table if not exists "better_supabase"."inbox_message_details" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."inbox_conversations" ("id") on delete cascade,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "author_type" text not null check ("author_type" in ('contact', 'agent', 'bot', 'system')),
  "format" text not null default 'text' check ("format" in ('text', 'markdown')),
  "external_id" text,
  "reply_to" uuid,
  "metadata" jsonb not null default '{}'::jsonb
);
create unique index if not exists inbox_message_details_external_idx on "better_supabase"."inbox_message_details" ("conversation_id", "external_id") where "external_id" is not null;
create index if not exists inbox_message_details_conversation_idx on "better_supabase"."inbox_message_details" ("conversation_id");
create index if not exists inbox_message_details_reply_idx on "better_supabase"."inbox_message_details" ("reply_to") where "reply_to" is not null;
alter table "better_supabase"."inbox_message_details" enable row level security;
revoke all on "better_supabase"."inbox_message_details" from public, anon, authenticated;
grant select on "better_supabase"."inbox_message_details" to authenticated;
grant all on "better_supabase"."inbox_message_details" to service_role;
drop policy if exists inbox_message_details_staff_read on "better_supabase"."inbox_message_details";
create policy inbox_message_details_staff_read on "better_supabase"."inbox_message_details"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

-- What happened to an outbound message on its channel. Status only moves
-- forward: queued, sent, delivered, read; failed before delivery.
create table if not exists "better_supabase"."inbox_message_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."inbox_message_details" ("message_id") on delete cascade,
  "channel" text not null,
  "status" text not null default 'queued' check ("status" in ('queued', 'sent', 'delivered', 'read', 'failed')),
  "external_id" text,
  "error" text,
  "attempts" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("message_id", "channel")
);
create index if not exists "inbox_message_deliveries_external_idx" on "better_supabase"."inbox_message_deliveries" ("channel", "external_id") where "external_id" is not null;
alter table "better_supabase"."inbox_message_deliveries" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."inbox_message_deliveries";
create trigger bsb_updated_at before update on "better_supabase"."inbox_message_deliveries"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inbox_message_deliveries" enable row level security;
revoke all on "better_supabase"."inbox_message_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."inbox_message_deliveries" to authenticated;
grant all on "better_supabase"."inbox_message_deliveries" to service_role;
drop policy if exists inbox_message_deliveries_staff_read on "better_supabase"."inbox_message_deliveries";
create policy inbox_message_deliveries_staff_read on "better_supabase"."inbox_message_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

-- Webhook deliveries from the channels, stored before the ack so a slow or
-- failed handler loses nothing. external_id dedupes a platform's retries.
create table if not exists "better_supabase"."inbox_inbound_events" (
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
create unique index if not exists "inbox_inbound_events_external_idx" on "better_supabase"."inbox_inbound_events" ("adapter", "external_id") where "external_id" is not null;
create index if not exists "inbox_inbound_events_status_idx" on "better_supabase"."inbox_inbound_events" ("status", "received_at");
create index if not exists "inbox_inbound_events_inbox_idx" on "better_supabase"."inbox_inbound_events" ("inbox_id");
alter table "better_supabase"."inbox_inbound_events" enable row level security;
revoke all on "better_supabase"."inbox_inbound_events" from public, anon, authenticated;
grant all on "better_supabase"."inbox_inbound_events" to service_role;

-- Approved templates for channels that need one outside a reply window
-- (WhatsApp after 24 hours). external_id is the platform's template name.
create table if not exists "better_supabase"."inbox_message_templates" (
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
create index if not exists "inbox_message_templates_inbox_idx" on "better_supabase"."inbox_message_templates" ("inbox_id");
alter table "better_supabase"."inbox_message_templates" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."inbox_message_templates";
create trigger bsb_updated_at before update on "better_supabase"."inbox_message_templates"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inbox_message_templates" enable row level security;
revoke all on "better_supabase"."inbox_message_templates" from public, anon, authenticated;
grant select on "better_supabase"."inbox_message_templates" to authenticated;
grant all on "better_supabase"."inbox_message_templates" to service_role;
drop policy if exists inbox_message_templates_staff_read on "better_supabase"."inbox_message_templates";
create policy inbox_message_templates_staff_read on "better_supabase"."inbox_message_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')));

-- Staff replies to send later. publish_due_inbox_messages sends each one
-- through the normal reply path once scheduled_for passes; until then only
-- its author sees it.
create table if not exists "better_supabase"."scheduled_inbox_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."inbox_conversations" ("id") on delete cascade,
  "author_id" uuid not null references auth.users (id) on delete cascade,
  "input" jsonb not null check (jsonb_typeof("input") = 'object'),
  "scheduled_for" timestamptz not null,
  "created_at" timestamptz not null default now()
);
create index if not exists scheduled_inbox_messages_due_idx on "better_supabase"."scheduled_inbox_messages" ("scheduled_for");
create index if not exists scheduled_inbox_messages_conversation_idx on "better_supabase"."scheduled_inbox_messages" ("conversation_id");
create index if not exists scheduled_inbox_messages_author_idx on "better_supabase"."scheduled_inbox_messages" ("author_id", "scheduled_for");
alter table "better_supabase"."scheduled_inbox_messages" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."scheduled_inbox_messages";
create trigger bsb_updated_at before update on "better_supabase"."scheduled_inbox_messages"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."scheduled_inbox_messages" enable row level security;
revoke all on "better_supabase"."scheduled_inbox_messages" from public, anon, authenticated;
grant select on "better_supabase"."scheduled_inbox_messages" to authenticated;
grant all on "better_supabase"."scheduled_inbox_messages" to service_role;
drop policy if exists scheduled_inbox_messages_author_read on "better_supabase"."scheduled_inbox_messages";
create policy scheduled_inbox_messages_author_read on "better_supabase"."scheduled_inbox_messages"
  for select to authenticated
  using ("author_id" = (select auth.uid()) and "tenant_id" in (select better_supabase.tenant_ids_with('inbox.reply')));

-- Reply drafts. A user draft belongs to its author, one open draft per
-- conversation; an ai draft has no author and every staff member who can
-- reply in the tenant sees it. status moves from draft to sent or discarded.
create table if not exists "better_supabase"."inbox_drafts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."inbox_conversations" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete cascade,
  "source" text not null default 'user' check ("source" in ('user', 'ai')),
  "input" jsonb not null check (jsonb_typeof("input") = 'object'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'discarded')),
  "metadata" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  constraint inbox_drafts_author_check check ("source" = 'ai' or "author_id" is not null)
);
create unique index if not exists inbox_drafts_open_key on "better_supabase"."inbox_drafts" ("conversation_id", "author_id") where "source" = 'user' and "status" = 'draft';
create index if not exists inbox_drafts_conversation_idx on "better_supabase"."inbox_drafts" ("conversation_id");
create index if not exists inbox_drafts_author_idx on "better_supabase"."inbox_drafts" ("author_id");
alter table "better_supabase"."inbox_drafts" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."inbox_drafts";
create trigger bsb_updated_at before update on "better_supabase"."inbox_drafts"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."inbox_drafts" enable row level security;
revoke all on "better_supabase"."inbox_drafts" from public, anon, authenticated;
grant select on "better_supabase"."inbox_drafts" to authenticated;
grant all on "better_supabase"."inbox_drafts" to service_role;
drop policy if exists inbox_drafts_read on "better_supabase"."inbox_drafts";
create policy inbox_drafts_read on "better_supabase"."inbox_drafts"
  for select to authenticated
  using (("author_id" = (select auth.uid()) or "source" = 'ai') and "tenant_id" in (select better_supabase.tenant_ids_with('inbox.reply')));

create or replace function "better_supabase"."inbox_contact_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select p."id" from "better_supabase"."people" p where p."user_id" = (select auth.uid());
end;
$$;
revoke execute on function "better_supabase"."inbox_contact_ids"() from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_contact_ids"() to authenticated, service_role;

-- Whether the caller may see a conversation: staff of its tenant, or the
-- signed-in contact it belongs to. write asks for the reply key instead.
create or replace function "better_supabase"."inbox_conversation_allowed"(conversation text, write boolean default false)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce((
    select (case when write then coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.reply'), false) else coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false) end)
      or exists (select 1 from "better_supabase"."people" p where p."id" = v."contact_id" and p."user_id" = (select auth.uid()))
    from "better_supabase"."inbox_conversations" v
    where v."id"::text = inbox_conversation_allowed.conversation
  ), false);
end;
$$;
revoke execute on function "better_supabase"."inbox_conversation_allowed"(text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_conversation_allowed"(text, boolean) to authenticated, service_role;

-- Whether the caller reads the conversation's internal notes: staff of its
-- tenant, never the contact.
create or replace function "better_supabase"."inbox_note_readable"(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."inbox_conversations" v
    where v."id" = inbox_note_readable.conversation and coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false)
  );
$$;
revoke execute on function "better_supabase"."inbox_note_readable"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_note_readable"(uuid) to authenticated, service_role;

-- What the messaging core's can_conversation answers for a conversation of
-- kind inbox: read for staff and the contact, send for repliers and the
-- contact (typing included), moderate for the manage key.
create or replace function "better_supabase"."inbox_can_conversation"(conversation uuid, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case inbox_can_conversation.action
    when 'read' then
      return "better_supabase"."inbox_conversation_allowed"(inbox_can_conversation.conversation::text);
    when 'send' then
      return "better_supabase"."inbox_conversation_allowed"(inbox_can_conversation.conversation::text, true);
    when 'moderate' then
      return exists (
        select 1 from "better_supabase"."inbox_conversations" v
        where v."id" = inbox_can_conversation.conversation and coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.manage'), false)
      );
    else
      return false;
  end case;
end;
$$;
revoke execute on function "better_supabase"."inbox_can_conversation"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_can_conversation"(uuid, text) to authenticated, service_role;

drop policy if exists conversations_read on "better_supabase"."inbox_conversations";
create policy conversations_read on "better_supabase"."inbox_conversations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')) or "contact_id" in (select "better_supabase"."inbox_contact_ids"()));

-- When the contact last read the conversation, for staff read receipts.
create or replace function "better_supabase"."inbox_contact_read_at"(conversation uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select k."last_read_at"
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."people" p on p."id" = v."contact_id"
    join "better_supabase"."conversation_members" k on k."conversation_id" = v."id" and k."user_id" = p."user_id"
    where v."id" = inbox_contact_read_at.conversation
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false))
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_contact_read_at"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_contact_read_at"(uuid) to authenticated, service_role;

-- The contact of a conversation the caller reads: the person, in the shape
-- the inbox has always returned. The person table's own policies ask for the
-- contacts read key, which agents and the contact need not hold.
create or replace function "better_supabase"."inbox_contact_json"(conversation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    return null;
  end if;
  return (
    select jsonb_build_object('id', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'avatar_url', p."avatar_url", 'user_id', p."user_id")
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."people" p on p."id" = v."contact_id"
    where v."id" = inbox_contact_json.conversation
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_contact_json"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_contact_json"(uuid) to authenticated, service_role;

-- A conversation with its contact and inbox, as the reads return it.
create or replace function "better_supabase"."inbox_conversation_json"(conversation uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select to_jsonb(v) || jsonb_build_object(
      'contact', "better_supabase"."inbox_contact_json"(v."id"),
      'inbox', (select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") from "better_supabase"."inboxes" i where i."id" = v."inbox_id"),
      'last_read_at', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())),
      'contact_read_at', "better_supabase"."inbox_contact_read_at"(v."id")
    )
    from "better_supabase"."inbox_conversations" v
    where v."id" = inbox_conversation_json.conversation
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_conversation_json"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_conversation_json"(uuid) to authenticated, service_role;

-- Messages of ids the caller reads, oldest first, as the messaging core
-- returns them (author, files and reactions included) with the inbox's own
-- fields. Staff also get notes and each outbound message's delivery. It runs
-- as its owner so a contact sees the files and reactions of their messages.
create or replace function "better_supabase"."inbox_messages_json"(ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  select array_agg(m."id") into v_ids
  from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = any (inbox_messages_json.ids)
    and m."sent_at" is not null
    and "better_supabase"."inbox_conversation_allowed"(d."conversation_id"::text)
    and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"));
  if v_ids is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(x.item || to_jsonb(d) || jsonb_build_object('delivery', case when "better_supabase"."inbox_note_readable"(d."conversation_id") then (
      select jsonb_build_object('status', l."status", 'channel', l."channel", 'error', l."error", 'updated_at', l."updated_at")
      from "better_supabase"."inbox_message_deliveries" l where l."message_id" = d."message_id"
      order by l."created_at" limit 1
    ) end) order by x.n), '[]'::jsonb)
    from jsonb_array_elements("better_supabase"."messaging_messages_json"(v_ids)) with ordinality as x (item, n)
    join "better_supabase"."inbox_message_details" d on d."message_id" = (x.item ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_messages_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."inbox_messages_json"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."create_inbox"(tenant uuid, name text, channel text default 'in_app', settings jsonb default '{}'::jsonb, bot_mode text default 'human', address text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox_team.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  return "better_supabase"."create_team"(create_inbox_team.tenant, create_inbox_team.name, null);
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
begin
  if not coalesce(present, true) then
    return "better_supabase"."remove_team_member"(set_inbox_team_member.team, member);
  end if;
  return "better_supabase"."add_team_member"(set_inbox_team_member.team, member);
end;
$$;
revoke execute on function "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) to authenticated, service_role;

-- Stores a message on a conversation as a core message with its inbox
-- fields, and moves the conversation along: the preview, the first response,
-- a reopen when the contact writes, the files, the bot job, the outbound job
-- and the notifications. input.attachments are ids of the author's uploads
-- to the conversation; input.files ({ url, name, content_type, size }) are a
-- channel's files, stored as pending attachments the service imports.
-- Callers check access. Returns the message id.
create or replace function "better_supabase"."inbox_add_message"(conversation uuid, input jsonb, author_type text, author uuid, direction text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_id uuid;
  v_at timestamptz := clock_timestamp();
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_body text := coalesce(input ->> 'body', '');
  v_mentions uuid[];
  v_uploads uuid[];
  v_file jsonb;
  v_moved integer;
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select d."message_id" into v_id from "better_supabase"."inbox_message_details" d
    where d."conversation_id" = v_conv."id" and d."external_id" = input ->> 'external_id';
    if found then
      return v_id;
    end if;
  end if;
  if v_kind not in ('message', 'note') then
    raise exception 'kind is message or note' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  v_uploads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(input -> 'attachments', '[]'::jsonb)) x);
  if length(btrim(v_body)) = 0 and cardinality(v_uploads) = 0 and coalesce(jsonb_array_length(input -> 'files'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "author_id", "kind", "body", "mentions", "sent_at", "created_at")
  values (v_conv."tenant_id", v_conv."id", inbox_add_message.author, v_kind, v_body, v_mentions, v_at, v_at)
  returning "id" into v_id;
  perform "better_supabase"."index_record_mentions"(v_id);
  insert into "better_supabase"."inbox_message_details" ("message_id", "tenant_id", "conversation_id", "direction", "author_type", "format", "external_id", "reply_to", "metadata")
  values (
    v_id, v_conv."tenant_id", v_conv."id", inbox_add_message.direction, inbox_add_message.author_type,
    coalesce(input ->> 'format', 'text'), input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  );
  if cardinality(v_uploads) > 0 then
    update "better_supabase"."attachments" x set "subject_type" = 'message', "subject_id" = v_id::text
    where x."id" = any (v_uploads)
      and x."organization_id" = v_conv."tenant_id"
      and x."subject_type" = 'conversation' and x."subject_id" = v_conv."id"::text
      and x."status" <> 'infected'
      and (inbox_add_message.author is null or x."uploaded_by" = inbox_add_message.author);
    get diagnostics v_moved = row_count;
    if v_moved <> cardinality(v_uploads) then
      raise exception 'attachments must be your uploads to this conversation' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
    end if;
  end if;
  for v_file in select f from jsonb_array_elements(coalesce(input -> 'files', '[]'::jsonb)) f loop
    insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by", "scan_detail")
    values (
      v_conv."tenant_id", 'message', v_id::text,
      left(coalesce(nullif(v_file ->> 'name', ''), 'file'), 255),
      lower(coalesce(nullif(v_file ->> 'content_type', ''), 'application/octet-stream')),
      coalesce((v_file ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', v_file)::text
    );
  end loop;
  if inbox_add_message.author is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."inbox_conversations" set
      "last_message_at" = v_at,
      "last_message_preview" = left(v_body, 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_at
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    perform "better_supabase".emit_event('inbox_message.received', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'messageId', v_id, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, 'inbox_message.received:' || v_id::text, 'better-supabase/inbox');
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_id, 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."inbox_message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_conv."tenant_id", v_id, v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_id, 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_id::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."inbox_add_message"(uuid, jsonb, text, uuid, text) from public, anon, authenticated;

-- Opens a conversation. Staff (the reply key) or the service name the
-- contact in input.contact (a person id, or the fields resolve_person
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
  v_contact uuid;
  v_contact_user uuid;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_start"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using start_conversation.inbox, start_conversation.input;
    end if;
  end;
  v_contact := "better_supabase"."resolve_person"(v_inbox."tenant_id", v_contact_input);
  select p."user_id" into v_contact_user from "better_supabase"."people" p where p."id" = v_contact;
  v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
  insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_id, v_inbox."tenant_id", v_inbox."id", v_contact, input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), coalesce(input ->> 'thread_id', 'inbox:' || v_inbox."id"::text || ':' || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact_user is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact_user)
    on conflict do nothing;
  end if;
  if v_conv."assignee_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_conv."assignee_id")
    on conflict do nothing;
  end if;
  insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."start_conversation"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."start_conversation"(uuid, jsonb) to authenticated, service_role;

-- Staff reply or add a note (input.kind = 'note'); the contact writes in
-- their own conversation; the service writes as the bot, the system, or the
-- contact (input.author_type). An agent's reply hands a bot conversation
-- over to staff. Returns the message as list_inbox_messages does.
create or replace function "better_supabase"."send_inbox_message"(conversation uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = send_inbox_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."people" p where p."id" = v_conv."contact_id" and p."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    if input ? 'files' then
      raise exception 'contacts attach their own uploads' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_message_send"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using send_inbox_message.conversation, send_inbox_message.input;
    end if;
  end;
  v_id := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return "better_supabase"."inbox_messages_json"(array[v_id]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."send_inbox_message"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_inbox_message"(uuid, jsonb) to authenticated, service_role;

-- A pending attachment on the conversation for the caller to upload to:
-- staff who reply, or the conversation's contact. Upload the file to its
-- bucket and object_path, call confirm_attachment, then pass its id in
-- send_inbox_message's input.attachments.
create or replace function "better_supabase"."create_inbox_attachment"(conversation uuid, name text, mime_type text, size bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" v where v."id" = create_inbox_attachment.conversation;
  if not found or (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(v_conv."id"::text, true) then
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by")
  values (v_conv."tenant_id", 'conversation', v_conv."id"::text, create_inbox_attachment.name, lower(create_inbox_attachment.mime_type), create_inbox_attachment.size, (select auth.uid()))
  returning * into v_row;
  return to_jsonb(v_row);
exception when check_violation then
  raise exception 'the file''s name, type or size is not allowed' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
end;
$$;
revoke execute on function "better_supabase"."create_inbox_attachment"(uuid, text, text, bigint) from public, anon;
grant execute on function "better_supabase"."create_inbox_attachment"(uuid, text, text, bigint) to authenticated, service_role;

-- A message that arrived on a channel, for the inbound handler: finds the
-- inbox's conversation for the thread (reopening it) or opens one, resolves
-- the contact by its identity on the channel, and stores the message once
-- per external_id. message.files are stored as pending attachments. Returns
-- { conversation_id, message_id, contact_id, created, duplicate }.
create or replace function "better_supabase"."record_inbound"(input jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact uuid;
  v_contact_user uuid;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_message uuid;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_input jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."resolve_person"(v_inbox."tenant_id", v_contact_input);
  select p."user_id" into v_contact_user from "better_supabase"."people" p where p."id" = v_contact;
    v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
    insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_id, v_inbox."tenant_id", v_inbox."id", v_contact, input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    if v_contact_user is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact_user)
    on conflict do nothing;
    end if;
    v_created := true;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  end if;
  if v_input ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_message_details" d where d."conversation_id" = v_conv."id" and d."external_id" = v_input ->> 'external_id');
  end if;
  v_message := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_input - 'kind' - 'attachments',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_message,
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
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (coalesce(assignee = (select auth.uid()), false) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_assign"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_conv."id", assign_conversation.assignee, assign_conversation.team;
    end if;
  end;
  update "better_supabase"."inbox_conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    perform "better_supabase".emit_event('inbox_conversation.assigned', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status", 'previousAssigneeId', v_before), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if assignee is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", assign_conversation.assignee)
    on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  if better_supabase.import_run() is null then
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
  end if;
      null;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
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
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and (snoozed_until is null or snoozed_until <= now()) then
    raise exception 'snoozing needs a snoozed_until in the future' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_status_change"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_conv."id", set_conversation_status.status;
    end if;
  end;
  update "better_supabase"."inbox_conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if status = 'snoozed' then
    perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.wake', 'conversation_id', v_conv."id"), delay => greatest(ceil(extract(epoch from (set_conversation_status.snoozed_until - now())))::integer, 0), dedupe_key => 'inbox-wake:' || v_conv."id"::text || ':' || extract(epoch from set_conversation_status.snoozed_until)::text, dedupe_running => false);
  end if;
  if v_before is distinct from status then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.resolved', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    elsif v_before = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_status_change"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
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
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = set_bot_mode.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_before := v_conv."bot_mode";
  update "better_supabase"."inbox_conversations" set "bot_mode" = mode where "id" = v_conv."id" returning * into v_conv;
  if v_before is distinct from mode then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason));
    if v_before = 'bot' and mode = 'human' then
  if better_supabase.import_run() is null then
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
  end if;
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$$;
revoke execute on function "better_supabase"."set_bot_mode"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_bot_mode"(uuid, text, text) to authenticated, service_role;

-- Marks the conversation read for the caller on their core member row. A
-- contact's read pings the conversation topic, for staff read receipts.
create or replace function "better_supabase"."mark_conversation_read"(conversation uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz := clock_timestamp();
  v_conv "better_supabase"."inbox_conversations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" v where v."id" = mark_conversation_read.conversation;
  insert into "better_supabase"."conversation_members" as k ("conversation_id", "tenant_id", "user_id", "last_read_at")
  values (v_conv."id", v_conv."tenant_id", (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = greatest(coalesce(k."last_read_at", excluded."last_read_at"), excluded."last_read_at");
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and exists (select 1 from "better_supabase"."people" p where p."id" = v_conv."contact_id" and p."user_id" = (select auth.uid())) then
    perform realtime.send(jsonb_build_object('conversation_id', v_conv."id"), 'read', 'messages:' || v_conv."id"::text, true);
  end if;
  return v_at;
end;
$$;
revoke execute on function "better_supabase"."mark_conversation_read"(uuid) from public, anon;
grant execute on function "better_supabase"."mark_conversation_read"(uuid) to authenticated, service_role;

-- Adds or removes the caller's reaction on a message (staff with the reply
-- key on a note); the service passes actor (a user id, or a name such as the
-- bot's). Returns the message's reactions.
create or replace function "better_supabase"."react_to_inbox_message"(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages"%rowtype;
  v_conversation uuid;
  v_who text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = react_to_inbox_message.message and m."deleted_at" is null;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  v_conversation := v_msg."conversation_id";
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(react_to_inbox_message.actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_conversation::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(react_to_inbox_message.emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  if coalesce(react_to_inbox_message.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (v_msg."tenant_id", 'message', v_msg."id"::text, v_who, case when v_who ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_who::uuid end, react_to_inbox_message.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" x
    where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text
      and x."actor" = v_who and x."emoji" = react_to_inbox_message.emoji;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', v_conversation, 'messageId', v_msg."id"),
      'message_updated',
      'messages:' || v_conversation::text,
      true
    );
  end if;
  return coalesce("better_supabase"."reaction_summary"(v_msg."tenant_id", 'message', array[v_msg."id"::text]) -> v_msg."id"::text, '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."react_to_inbox_message"(uuid, text, boolean, text) from public, anon;
grant execute on function "better_supabase"."react_to_inbox_message"(uuid, text, boolean, text) to authenticated, service_role;

-- The author (or the service) edits a message's body, or deletes it: the
-- message stays as a tombstone with an empty body and its files go.
create or replace function "better_supabase"."edit_inbox_message"(message uuid, body text default null, remove boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_msg "better_supabase"."messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = edit_inbox_message.message
  for update of m;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and coalesce(v_msg."author_id" = (select auth.uid()), false))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."deleted_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  if length(coalesce(edit_inbox_message.body, '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  update "better_supabase"."messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_inbox_message.body, "body") end,
    "deleted_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  if coalesce(remove, false) then
    delete from "better_supabase"."attachments" x where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text;
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_msg."id"]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."edit_inbox_message"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."edit_inbox_message"(uuid, text, boolean) to authenticated, service_role;

-- Conversations the caller reads (staff of the tenant, or a contact's own),
-- newest activity first. filter: inbox_id, status ('all' for every status),
-- assignee ('me', 'unassigned' or an id), team_id, contact_id, search,
-- before ({ last_message_at, id } of the previous page's last item), limit.
create or replace function "better_supabase"."list_inbox_conversations"(tenant uuid default null, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg("better_supabase"."inbox_conversation_json"(page."id") || jsonb_build_object('unread', page.unread) order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
    from (
      select v."id", v."last_message_at",
        v."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz) as unread
      from "better_supabase"."inbox_conversations" v
      where (list_inbox_conversations.tenant is null or v."tenant_id" = list_inbox_conversations.tenant)
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
          or "better_supabase"."inbox_contact_json"(v."id") ->> 'name' ilike '%' || (filter ->> 'search') || '%'
          or "better_supabase"."inbox_contact_json"(v."id") ->> 'email' ilike '%' || (filter ->> 'search') || '%')
        and (filter -> 'before' is null
          or (v."last_message_at", v."id") < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
      order by v."last_message_at" desc, v."id" desc
      limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
    ) page
  );
end;
$$;
revoke execute on function "better_supabase"."list_inbox_conversations"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inbox_conversations"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_conversation"(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."inbox_conversation_json"(v."id") from "better_supabase"."inbox_conversations" v where v."id" = conversation;
$$;
revoke execute on function "better_supabase"."get_conversation"(uuid) from public, anon;
grant execute on function "better_supabase"."get_conversation"(uuid) to authenticated, service_role;

-- A page of messages, oldest first: the newest sent before the given instant,
-- or with after the oldest sent after it. Staff also get notes and each
-- outbound message's delivery.
create or replace function "better_supabase"."list_inbox_messages"(conversation uuid, before timestamptz default null, max integer default 50, after timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not "better_supabase"."inbox_conversation_allowed"(list_inbox_messages.conversation::text) then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."inbox_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_inbox_messages.conversation
      and m."sent_at" is not null
      and (list_inbox_messages.before is null or m."sent_at" < list_inbox_messages.before)
      and (list_inbox_messages.after is null or m."sent_at" > list_inbox_messages.after)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(list_inbox_messages.conversation))
    order by
      case when list_inbox_messages.after is null then m."sent_at" end desc,
      case when list_inbox_messages.after is null then m."id" end desc,
      m."sent_at", m."id"
    limit least(greatest(coalesce(list_inbox_messages.max, 50), 1), 200)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_inbox_messages"(uuid, timestamptz, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_inbox_messages"(uuid, timestamptz, integer, timestamptz) to authenticated, service_role;

-- One message as list_inbox_messages returns it, for a Realtime ping.
create or replace function "better_supabase"."get_inbox_message"(message uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select "better_supabase"."inbox_messages_json"(array[get_inbox_message.message]) -> 0;
$$;
revoke execute on function "better_supabase"."get_inbox_message"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inbox_message"(uuid) to authenticated, service_role;

-- The conversation's activity log, for staff.
create or replace function "better_supabase"."list_conversation_events"(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."id"), '[]'::jsonb)
  from "better_supabase"."inbox_conversation_events" e where e."conversation_id" = list_conversation_events.conversation;
$$;
revoke execute on function "better_supabase"."list_conversation_events"(uuid) from public, anon;
grant execute on function "better_supabase"."list_conversation_events"(uuid) to authenticated, service_role;

-- Counts of open conversations for the caller: all, assigned to them,
-- unassigned, and those with activity since they last read them.
create or replace function "better_supabase"."inbox_counts"(tenant uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select jsonb_build_object(
      'open', count(*),
      'mine', count(*) filter (where v."assignee_id" = (select auth.uid())),
      'unassigned', count(*) filter (where v."assignee_id" is null),
      'unread', count(*) filter (where v."last_message_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
        and (v."assignee_id" is null or v."assignee_id" = (select auth.uid())))
    )
    from "better_supabase"."inbox_conversations" v
    left join "better_supabase"."conversation_members" k on k."conversation_id" = v."id" and k."user_id" = (select auth.uid())
    where v."tenant_id" = inbox_counts.tenant and v."status" = 'open'
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_counts"(uuid) from public, anon;
grant execute on function "better_supabase"."inbox_counts"(uuid) to authenticated, service_role;

-- After posting an outbound message on its channel: records the platform's
-- id and the status.
create or replace function "better_supabase"."record_delivery"(message uuid, channel text, external_id text default null, status text default 'sent', error text default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."inbox_message_deliveries"%rowtype;
begin
  insert into "better_supabase"."inbox_message_deliveries" as d ("tenant_id", "message_id", "channel", "external_id", "status", "error", "attempts")
  select m."tenant_id", m."message_id", record_delivery.channel, record_delivery.external_id, coalesce(record_delivery.status, 'sent'), record_delivery.error, 1
  from "better_supabase"."inbox_message_details" m where m."message_id" = record_delivery.message
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
  update "better_supabase"."inbox_message_deliveries" d set "status" = status, "error" = coalesce(error, d."error")
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
  insert into "better_supabase"."inbox_inbound_events" ("adapter", "body", "external_id", "headers", "inbox_id", "tenant_id")
  values (adapter, body, external_id, coalesce(headers, '{}'::jsonb), inbox, tenant)
  on conflict do nothing
  returning "id" into v_id;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'duplicate', false);
  end if;
  select e."id" into v_id from "better_supabase"."inbox_inbound_events" e where e."adapter" = adapter and e."external_id" = external_id;
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
  update "better_supabase"."inbox_inbound_events" e set
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
    select * from "better_supabase"."inbox_inbound_events" x
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
  delete from "better_supabase"."inbox_inbound_events" e where e."id" in (
    select x."id" from "better_supabase"."inbox_inbound_events" x
    where (x."received_at" < now() - least(coalesce(older_than, interval '30 days'), "better_supabase"."retention_floor"('inbound_events'))
      and x."received_at" < now() - coalesce("better_supabase"."retention_for"('inbound_events', (x."tenant_id")::text), coalesce(older_than, interval '30 days'))
      and not "better_supabase"."is_held"('inbound_events', (x."tenant_id")::text))
      and x."status" in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_inbound_events"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_inbound_events"(interval, integer) to service_role;

create or replace function "better_supabase"."upsert_message_template"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inbox_message_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inbox_message_templates" as t ("tenant_id", "inbox_id", "name", "channel", "language", "body", "variables", "external_id")
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."inbox_message_templates" where "id" = delete_message_template.template;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  delete from "better_supabase"."inbox_message_templates" t where t."id" = delete_message_template.template;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_message_template"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_message_template"(uuid) to authenticated, service_role;

-- Erases a contact for a data subject request: the person, their identities
-- and their conversations with their messages, files, deliveries and events.
-- Returns { conversations, messages, attachments }; attachments are the
-- { bucket, path } of the stored files the caller still has to remove.
create or replace function "better_supabase"."purge_contact"(contact uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_ids uuid[];
  v_messages integer;
  v_paths jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id" into v_tenant from "better_supabase"."people" p where p."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_ids := array(select v."id" from "better_supabase"."inbox_conversations" v where v."contact_id" = purge_contact.contact);
  select count(*)::integer into v_messages from "better_supabase"."messages" m where m."conversation_id" = any (v_ids);
  with gone as (
    delete from "better_supabase"."attachments" x
    where (x."subject_type" = 'conversation' and x."subject_id" = any (array(select i::text from unnest(v_ids) i)))
      or (x."subject_type" = 'message' and x."subject_id" in (
        select m."id"::text from "better_supabase"."messages" m where m."conversation_id" = any (v_ids)))
    returning x."bucket" as bucket, x."object_path" as path, x."uploaded_at" as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', g.bucket, 'path', g.path)) filter (where g.uploaded_at is not null), '[]'::jsonb)
  into v_paths from gone g;
  delete from "better_supabase"."conversations" k where k."id" = any (v_ids);
  delete from "better_supabase"."person_identities" i where i."person_id" = purge_contact.contact;
  update "better_supabase"."people" p set "merged_into" = null where p."merged_into" = purge_contact.contact;
  delete from "better_supabase"."people" p where p."id" = purge_contact.contact;
  return jsonb_build_object('conversations', cardinality(v_ids), 'messages', v_messages, 'attachments', v_paths);
end;
$$;
revoke execute on function "better_supabase"."purge_contact"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_contact"(uuid) to authenticated, service_role;

-- Files a channel sent that still wait for their import, oldest first:
-- { id, conversation_id, message_id, tenant_id, bucket, object_path, name,
-- mime_type, source }. source is the channel's file ({ url, name,
-- content_type, size }) or, for files copied from an older inbox,
-- { bucket, path }. Upload the bytes to bucket and object_path, then call
-- confirm_attachment as the service, or inbox_file_failed.
create or replace function "better_supabase"."pending_inbox_files"(max integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'conversation_id', d."conversation_id",
    'message_id', d."message_id",
    'tenant_id', x."organization_id",
    'bucket', x."bucket",
    'object_path', x."object_path",
    'name', x."name",
    'mime_type', x."mime_type",
    'source', x."scan_detail"::jsonb -> 'source'
  ) order by x."created_at", x."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."attachments" y
    where y."status" = 'pending' and y."uploaded_at" is null
      and y."subject_type" = 'message'
      and y."scan_detail" is not null and y."scan_detail" like '{"source"%'
    order by y."created_at", y."id"
    limit least(greatest(coalesce(max, 50), 1), 500)
  ) x
  join "better_supabase"."inbox_message_details" d on d."message_id"::text = x."subject_id";
$$;
revoke execute on function "better_supabase"."pending_inbox_files"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_inbox_files"(integer) to service_role;

-- Marks a channel file that could not be imported, with the reason.
create or replace function "better_supabase"."inbox_file_failed"(attachment uuid, detail text default null)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  update "better_supabase"."attachments" x set
    "status" = 'failed',
    "scan_detail" = coalesce(inbox_file_failed.detail, 'import failed'),
    "scanned_at" = now()
  where x."id" = inbox_file_failed.attachment and x."status" = 'pending' and x."uploaded_at" is null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."inbox_file_failed"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."inbox_file_failed"(uuid, text) to service_role;

-- Reopens snoozed conversations whose time came: the delayed job from
-- set_conversation_status, or a periodic sweep. Each one logs unsnoozed, emits
-- inbox_conversation.unsnoozed and tells the assignee (or the inbox's members).
create or replace function "better_supabase"."wake_snoozed_conversations"()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_until timestamptz;
  v_count integer := 0;
  v_claims text;
begin
  for v_conv in
    select * from "better_supabase"."inbox_conversations"
    where "status" = 'snoozed' and "snoozed_until" <= now()
    order by "snoozed_until"
    for update skip locked
  loop
    v_until := v_conv."snoozed_until";
    update "better_supabase"."inbox_conversations" set "status" = 'open', "snoozed_until" = null
    where "id" = v_conv."id"
    returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
    values (v_conv."tenant_id", v_conv."id", 'unsnoozed', null, jsonb_build_object('snoozed_until', v_until));
    perform "better_supabase".emit_event('inbox_conversation.unsnoozed', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.snooze_ended',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', coalesce(v_conv."subject", v_conv."last_message_preview"),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.snooze_ended:' || v_conv."id"::text || ':' || extract(epoch from v_until)::text,
      'data', jsonb_build_object('conversationId', v_conv."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."wake_snoozed_conversations"() from public, anon, authenticated;
grant execute on function "better_supabase"."wake_snoozed_conversations"() to service_role;

-- Schedules a staff reply on the conversation for scheduled_for. Only
-- messages: notes post right away. The input is the one send_inbox_message
-- takes, without the service's fields.
create or replace function "better_supabase"."schedule_inbox_message"(conversation uuid, input jsonb, scheduled_for timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = schedule_inbox_message.conversation;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if (select auth.uid()) is null or not coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    raise exception 'not allowed to reply in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'kind', 'message') <> 'message' then
    raise exception 'only messages can be scheduled' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  if length(btrim(coalesce(v_input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(v_input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(coalesce(v_input ->> 'body', '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  if schedule_inbox_message.scheduled_for is null or schedule_inbox_message.scheduled_for <= now() then
    raise exception 'scheduled_for must be in the future' using errcode = '22023', hint = 'INBOX_SCHEDULE_TIME';
  end if;
  insert into "better_supabase"."scheduled_inbox_messages" ("tenant_id", "conversation_id", "author_id", "input", "scheduled_for")
  values (v_conv."tenant_id", v_conv."id", (select auth.uid()), v_input, schedule_inbox_message.scheduled_for)
  returning * into v_row;
  perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.publish', 'scheduled_id', v_row."id"), delay => greatest(ceil(extract(epoch from (v_row."scheduled_for" - now())))::integer, 0), dedupe_key => 'inbox-publish:' || v_row."id"::text || ':' || extract(epoch from v_row."scheduled_for")::text, dedupe_running => false);
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."schedule_inbox_message"(uuid, jsonb, timestamptz) from public, anon;
grant execute on function "better_supabase"."schedule_inbox_message"(uuid, jsonb, timestamptz) to authenticated, service_role;

-- The caller's scheduled messages, soonest first; on one conversation when
-- conversation is set.
create or replace function "better_supabase"."list_scheduled_inbox_messages"(conversation uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s."scheduled_for", s."id"), '[]'::jsonb)
  from "better_supabase"."scheduled_inbox_messages" s
  where s."author_id" = (select auth.uid())
    and (list_scheduled_inbox_messages.conversation is null or s."conversation_id" = list_scheduled_inbox_messages.conversation);
$$;
revoke execute on function "better_supabase"."list_scheduled_inbox_messages"(uuid) from public, anon;
grant execute on function "better_supabase"."list_scheduled_inbox_messages"(uuid) to authenticated, service_role;

-- Moves the caller's scheduled message to another time in the future.
create or replace function "better_supabase"."reschedule_inbox_message"(scheduled uuid, scheduled_for timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."scheduled_inbox_messages" where "id" = reschedule_inbox_message.scheduled and "author_id" = (select auth.uid()) for update;
  if not found then
    raise exception 'scheduled message not found' using errcode = 'P0002', hint = 'SCHEDULED_MESSAGE_NOT_FOUND';
  end if;
  if reschedule_inbox_message.scheduled_for is null or reschedule_inbox_message.scheduled_for <= now() then
    raise exception 'scheduled_for must be in the future' using errcode = '22023', hint = 'INBOX_SCHEDULE_TIME';
  end if;
  update "better_supabase"."scheduled_inbox_messages" set "scheduled_for" = reschedule_inbox_message.scheduled_for
  where "id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.publish', 'scheduled_id', v_row."id"), delay => greatest(ceil(extract(epoch from (v_row."scheduled_for" - now())))::integer, 0), dedupe_key => 'inbox-publish:' || v_row."id"::text || ':' || extract(epoch from v_row."scheduled_for")::text, dedupe_running => false);
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."reschedule_inbox_message"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."reschedule_inbox_message"(uuid, timestamptz) to authenticated, service_role;

-- Deletes the caller's scheduled message before it is sent.
create or replace function "better_supabase"."cancel_inbox_message"(scheduled uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."scheduled_inbox_messages" where "id" = cancel_inbox_message.scheduled and "author_id" = (select auth.uid()) for update;
  if not found then
    raise exception 'scheduled message not found' using errcode = 'P0002', hint = 'SCHEDULED_MESSAGE_NOT_FOUND';
  end if;
  delete from "better_supabase"."scheduled_inbox_messages" where "id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_inbox_message"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_inbox_message"(uuid) to authenticated, service_role;

-- Sends the scheduled messages whose time came, oldest first, as their
-- authors. A message whose author can no longer reply is dropped. Returns
-- the number sent.
create or replace function "better_supabase"."publish_due_inbox_messages"(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."scheduled_inbox_messages"%rowtype;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."scheduled_inbox_messages"
    where "scheduled_for" <= now()
    order by "scheduled_for", "id"
    limit greatest(coalesce(max_rows, 100), 1)
    for update skip locked
  loop
    delete from "better_supabase"."scheduled_inbox_messages" where "id" = v_row."id";
    if not coalesce(better_supabase.can_user(v_row."author_id", 'tenant', v_row."tenant_id", 'inbox.reply'), false) then
      continue;
    end if;
    perform "better_supabase"."inbox_add_message"(v_row."conversation_id", v_row."input", 'agent', v_row."author_id", 'outbound');
    select * into v_conv from "better_supabase"."inbox_conversations" where "id" = v_row."conversation_id";
    if v_conv."bot_mode" = 'bot' then
      update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
      insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
    values (v_conv."tenant_id", v_conv."id", 'handoff', v_row."author_id", jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_due_inbox_messages"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."publish_due_inbox_messages"(integer) to service_role;

-- Saves the caller's draft reply on a conversation: the one open draft is
-- replaced, else a new one starts. The input is the one send_inbox_message
-- takes, without the service's fields; an empty body is fine until it sends.
create or replace function "better_supabase"."save_inbox_draft"(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."inbox_drafts"%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
  v_metadata jsonb := save_inbox_draft.metadata;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = save_inbox_draft.conversation;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if (select auth.uid()) is null or not coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    raise exception 'not allowed to reply in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(coalesce(v_input ->> 'body', '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  if v_metadata is not null and jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be an object' using errcode = '22023', hint = 'INBOX_DRAFT_METADATA';
  end if;
  update "better_supabase"."inbox_drafts" x set "input" = v_input, "metadata" = coalesce(v_metadata, x."metadata")
  where x."conversation_id" = v_conv."id" and x."author_id" = (select auth.uid())
    and x."source" = 'user' and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."inbox_drafts" ("tenant_id", "conversation_id", "author_id", "source", "input", "metadata")
  values (v_conv."tenant_id", v_conv."id", (select auth.uid()), 'user', v_input, coalesce(v_metadata, '{}'::jsonb))
  returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_inbox_draft"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."save_inbox_draft"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Adds an ai draft to a conversation for its staff to review. The service
-- role only: the model runs on the server.
create or replace function "better_supabase"."suggest_inbox_draft"(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."inbox_drafts"%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
  v_metadata jsonb := suggest_inbox_draft.metadata;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = suggest_inbox_draft.conversation;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if length(coalesce(v_input ->> 'body', '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  if v_metadata is not null and jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be an object' using errcode = '22023', hint = 'INBOX_DRAFT_METADATA';
  end if;
  insert into "better_supabase"."inbox_drafts" ("tenant_id", "conversation_id", "author_id", "source", "input", "metadata")
  values (v_conv."tenant_id", v_conv."id", null, 'ai', v_input, coalesce(v_metadata, '{}'::jsonb))
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."suggest_inbox_draft"(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."suggest_inbox_draft"(uuid, jsonb, jsonb) to service_role;

-- The open drafts the caller sees, newest first: their own and the ai
-- drafts of their tenants, on one conversation when conversation is set.
create or replace function "better_supabase"."list_inbox_drafts"(conversation uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(d) order by d."updated_at" desc, d."id"), '[]'::jsonb)
  from "better_supabase"."inbox_drafts" d
  where d."status" = 'draft'
    and (list_inbox_drafts.conversation is null or d."conversation_id" = list_inbox_drafts.conversation);
$$;
revoke execute on function "better_supabase"."list_inbox_drafts"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inbox_drafts"(uuid) to authenticated, service_role;

-- Sends a draft as the caller through send_inbox_message, with input's
-- fields over the draft's, and marks it sent. Returns the message.
create or replace function "better_supabase"."send_inbox_draft"(draft uuid, input jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inbox_drafts"%rowtype;
  v_message jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inbox_drafts" where "id" = send_inbox_draft.draft for update;
  if not found or v_row."status" <> 'draft' or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_row."author_id" = (select auth.uid()) or v_row."source" = 'ai') and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inbox.reply'), false))) then
    raise exception 'draft not found' using errcode = 'P0002', hint = 'INBOX_DRAFT_NOT_FOUND';
  end if;
  v_message := "better_supabase"."send_inbox_message"(v_row."conversation_id", v_row."input" || (coalesce(send_inbox_draft.input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller'));
  update "better_supabase"."inbox_drafts" set "status" = 'sent' where "id" = v_row."id";
  return v_message;
end;
$$;
revoke execute on function "better_supabase"."send_inbox_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_inbox_draft"(uuid, jsonb) to authenticated, service_role;

-- Discards a draft the caller can act on.
create or replace function "better_supabase"."discard_inbox_draft"(draft uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inbox_drafts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inbox_drafts" where "id" = discard_inbox_draft.draft for update;
  if not found or v_row."status" <> 'draft' or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_row."author_id" = (select auth.uid()) or v_row."source" = 'ai') and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inbox.reply'), false))) then
    raise exception 'draft not found' using errcode = 'P0002', hint = 'INBOX_DRAFT_NOT_FOUND';
  end if;
  update "better_supabase"."inbox_drafts" set "status" = 'discarded' where "id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."discard_inbox_draft"(uuid) from public, anon;
grant execute on function "better_supabase"."discard_inbox_draft"(uuid) to authenticated, service_role;

-- A core message in an inbox conversation pings the staff topic. The
-- messaging module attaches it to its messages table.
create or replace function "better_supabase"."inbox_message_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
begin
  if not to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null or new."sent_at" is null then
    return null;
  end if;
  select v."tenant_id"::text into v_tenant from "better_supabase"."inbox_conversations" v where v."id" = new."conversation_id";
  if v_tenant is not null then
    perform realtime.send(jsonb_build_object('conversation_id', new."conversation_id", 'message_id', new."id", 'kind', new."kind"), case when tg_op = 'INSERT' or old."sent_at" is null then 'message' else 'message_updated' end, 'inbox:org:' || v_tenant::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_message_broadcast"() from public, anon, authenticated;

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
    perform realtime.send(v_payload, 'conversation', 'messages:' || new."id"::text, true);
    perform realtime.send(v_payload, 'conversation', 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_conversation_broadcast"() from public, anon, authenticated;
drop trigger if exists conversations_broadcast on "better_supabase"."inbox_conversations";
create trigger conversations_broadcast after insert or update on "better_supabase"."inbox_conversations"
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
      jsonb_build_object('conversation_id', d."conversation_id", 'message_id', new."message_id", 'status', new."status"),
      'delivery',
      'inbox:org:' || new."tenant_id"::text,
      true
    )
    from "better_supabase"."inbox_message_details" d where d."message_id" = new."message_id";
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."inbox_delivery_broadcast"() from public, anon, authenticated;
drop trigger if exists "inbox_message_deliveries_broadcast" on "better_supabase"."inbox_message_deliveries";
create trigger "inbox_message_deliveries_broadcast" after insert or update of "status" on "better_supabase"."inbox_message_deliveries"
  for each row execute function "better_supabase"."inbox_delivery_broadcast"();

-- Staff join inbox:org:<tenant>. A conversation's own topic, with typing
-- and presence, is the messaging core's.
do $$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_inbox_receive on realtime.messages;
create policy bsb_inbox_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'inbox:org:%'
        and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('inbox.read') x));
    drop policy if exists "bsb_inbox_broadcast" on realtime.messages;
  end if;
end;
$$;

create or replace function "better_supabase"."inbox_file_allowed"(bucket text, object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from "better_supabase"."attachments" a
    join "better_supabase"."messages" m on a."subject_type" = 'message' and m."id"::text = a."subject_id"
    join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
    where a."bucket" = inbox_file_allowed.bucket and a."object_path" = inbox_file_allowed.object_name
      and a."status" = 'clean'
      and m."deleted_at" is null
      and "better_supabase"."inbox_conversation_allowed"(d."conversation_id"::text)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"))
  );
end;
$$;
revoke execute on function "better_supabase"."inbox_file_allowed"(text, text) from public, anon;
grant execute on function "better_supabase"."inbox_file_allowed"(text, text) to authenticated, service_role;

do $$
begin
  if to_regclass('storage.objects') is not null then
        drop policy if exists bsb_inbox_files_read on storage.objects;
create policy bsb_inbox_files_read on storage.objects
  for select to authenticated
  using ("better_supabase"."inbox_file_allowed"(bucket_id, name));
    drop policy if exists "bsb_inbox_files_write" on storage.objects;
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."inboxes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inboxes";
create policy bsb_tenant_scope_select on "better_supabase"."inboxes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inboxes";
create policy bsb_tenant_scope_insert on "better_supabase"."inboxes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inboxes";
create policy bsb_tenant_scope_update on "better_supabase"."inboxes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inboxes";
create policy bsb_tenant_scope_delete on "better_supabase"."inboxes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_conversations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_conversations";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_conversations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')) or "contact_id" in (select "better_supabase"."inbox_contact_ids"()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_conversations";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_conversations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_conversations";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_conversations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_conversations";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_conversations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_conversation_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_conversation_events";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_conversation_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_conversation_events";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_conversation_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_conversation_events";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_conversation_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_conversation_events";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_conversation_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_details";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_details";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_message_details" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_details";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_message_details" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_details";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_message_details" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_details";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_message_details" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_message_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_message_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_message_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_message_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_message_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_message_templates";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_message_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inbox.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_message_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_message_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_message_templates";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_message_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_message_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_message_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."scheduled_inbox_messages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."scheduled_inbox_messages";
create policy bsb_tenant_scope_select on "better_supabase"."scheduled_inbox_messages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("author_id" = (select auth.uid()) and "tenant_id" in (select better_supabase.tenant_ids_with('inbox.reply')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."scheduled_inbox_messages";
create policy bsb_tenant_scope_insert on "better_supabase"."scheduled_inbox_messages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."scheduled_inbox_messages";
create policy bsb_tenant_scope_update on "better_supabase"."scheduled_inbox_messages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."scheduled_inbox_messages";
create policy bsb_tenant_scope_delete on "better_supabase"."scheduled_inbox_messages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inbox_drafts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inbox_drafts";
create policy bsb_tenant_scope_select on "better_supabase"."inbox_drafts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("author_id" = (select auth.uid()) or "source" = 'ai') and "tenant_id" in (select better_supabase.tenant_ids_with('inbox.reply')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inbox_drafts";
create policy bsb_tenant_scope_insert on "better_supabase"."inbox_drafts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inbox_drafts";
create policy bsb_tenant_scope_update on "better_supabase"."inbox_drafts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inbox_drafts";
create policy bsb_tenant_scope_delete on "better_supabase"."inbox_drafts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.inboxes', target_type => 'inbox', event_prefix => 'inbox', deferred => true);
end;
$$;

-- blocks.inbox.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."inbox_contact_ids"();
drop function if exists "api"."inbox_conversation_allowed"(text, boolean);
drop function if exists "api"."inbox_note_readable"(uuid);
drop function if exists "api"."inbox_can_conversation"(uuid, text);
drop function if exists "api"."inbox_contact_read_at"(uuid);
drop function if exists "api"."inbox_contact_json"(uuid);
drop function if exists "api"."inbox_conversation_json"(uuid);
drop function if exists "api"."inbox_messages_json"(uuid[]);
drop function if exists "api"."inbox_file_allowed"(text, text);

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

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

create or replace function "api"."start_conversation"(inbox uuid, input jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_conversation"($1, $2) $$;
revoke execute on function "api"."start_conversation"(uuid, jsonb) from public, anon;
grant execute on function "api"."start_conversation"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."send_inbox_message"(conversation uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_inbox_message"($1, $2) $$;
revoke execute on function "api"."send_inbox_message"(uuid, jsonb) from public, anon;
grant execute on function "api"."send_inbox_message"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."create_inbox_attachment"(conversation uuid, name text, mime_type text, size bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_inbox_attachment"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_inbox_attachment"(uuid, text, text, bigint) from public, anon;
grant execute on function "api"."create_inbox_attachment"(uuid, text, text, bigint) to authenticated, service_role;

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

create or replace function "api"."react_to_inbox_message"(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."react_to_inbox_message"($1, $2, $3, $4) $$;
revoke execute on function "api"."react_to_inbox_message"(uuid, text, boolean, text) from public, anon;
grant execute on function "api"."react_to_inbox_message"(uuid, text, boolean, text) to authenticated, service_role;

create or replace function "api"."edit_inbox_message"(message uuid, body text default null, remove boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."edit_inbox_message"($1, $2, $3) $$;
revoke execute on function "api"."edit_inbox_message"(uuid, text, boolean) from public, anon;
grant execute on function "api"."edit_inbox_message"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."list_inbox_conversations"(tenant uuid default null, filter jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inbox_conversations"($1, $2) $$;
revoke execute on function "api"."list_inbox_conversations"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_inbox_conversations"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_conversation"(conversation uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_conversation"($1) $$;
revoke execute on function "api"."get_conversation"(uuid) from public, anon;
grant execute on function "api"."get_conversation"(uuid) to authenticated, service_role;

create or replace function "api"."list_inbox_messages"(conversation uuid, before timestamptz default null, max integer default 50, after timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inbox_messages"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_inbox_messages"(uuid, timestamptz, integer, timestamptz) from public, anon;
grant execute on function "api"."list_inbox_messages"(uuid, timestamptz, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."get_inbox_message"(message uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_inbox_message"($1) $$;
revoke execute on function "api"."get_inbox_message"(uuid) from public, anon;
grant execute on function "api"."get_inbox_message"(uuid) to authenticated, service_role;

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

create or replace function "api"."pending_inbox_files"(max integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_inbox_files"($1) $$;
revoke execute on function "api"."pending_inbox_files"(integer) from public, anon, authenticated;
grant execute on function "api"."pending_inbox_files"(integer) to service_role;

create or replace function "api"."inbox_file_failed"(attachment uuid, detail text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inbox_file_failed"($1, $2) $$;
revoke execute on function "api"."inbox_file_failed"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."inbox_file_failed"(uuid, text) to service_role;

create or replace function "api"."wake_snoozed_conversations"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."wake_snoozed_conversations"() $$;
revoke execute on function "api"."wake_snoozed_conversations"() from public, anon, authenticated;
grant execute on function "api"."wake_snoozed_conversations"() to service_role;

create or replace function "api"."schedule_inbox_message"(conversation uuid, input jsonb, scheduled_for timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_inbox_message"($1, $2, $3) $$;
revoke execute on function "api"."schedule_inbox_message"(uuid, jsonb, timestamptz) from public, anon;
grant execute on function "api"."schedule_inbox_message"(uuid, jsonb, timestamptz) to authenticated, service_role;

create or replace function "api"."list_scheduled_inbox_messages"(conversation uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_scheduled_inbox_messages"($1) $$;
revoke execute on function "api"."list_scheduled_inbox_messages"(uuid) from public, anon;
grant execute on function "api"."list_scheduled_inbox_messages"(uuid) to authenticated, service_role;

create or replace function "api"."reschedule_inbox_message"(scheduled uuid, scheduled_for timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reschedule_inbox_message"($1, $2) $$;
revoke execute on function "api"."reschedule_inbox_message"(uuid, timestamptz) from public, anon;
grant execute on function "api"."reschedule_inbox_message"(uuid, timestamptz) to authenticated, service_role;

create or replace function "api"."cancel_inbox_message"(scheduled uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_inbox_message"($1) $$;
revoke execute on function "api"."cancel_inbox_message"(uuid) from public, anon;
grant execute on function "api"."cancel_inbox_message"(uuid) to authenticated, service_role;

create or replace function "api"."publish_due_inbox_messages"(max_rows integer default 100)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_due_inbox_messages"($1) $$;
revoke execute on function "api"."publish_due_inbox_messages"(integer) from public, anon, authenticated;
grant execute on function "api"."publish_due_inbox_messages"(integer) to service_role;

create or replace function "api"."save_inbox_draft"(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_inbox_draft"($1, $2, $3) $$;
revoke execute on function "api"."save_inbox_draft"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."save_inbox_draft"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."suggest_inbox_draft"(conversation uuid, input jsonb, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_inbox_draft"($1, $2, $3) $$;
revoke execute on function "api"."suggest_inbox_draft"(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function "api"."suggest_inbox_draft"(uuid, jsonb, jsonb) to service_role;

create or replace function "api"."list_inbox_drafts"(conversation uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inbox_drafts"($1) $$;
revoke execute on function "api"."list_inbox_drafts"(uuid) from public, anon;
grant execute on function "api"."list_inbox_drafts"(uuid) to authenticated, service_role;

create or replace function "api"."send_inbox_draft"(draft uuid, input jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_inbox_draft"($1, $2) $$;
revoke execute on function "api"."send_inbox_draft"(uuid, jsonb) from public, anon;
grant execute on function "api"."send_inbox_draft"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."discard_inbox_draft"(draft uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."discard_inbox_draft"($1) $$;
revoke execute on function "api"."discard_inbox_draft"(uuid) from public, anon;
grant execute on function "api"."discard_inbox_draft"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
