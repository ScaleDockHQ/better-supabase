-- better-supabase module: ai-chat (0.5.1)
-- @bs-module ai-chat@2 managed
-- Chats, projects and a branching message tree in the canonical AI message format, with runs (and the id of a durable engine's run), run steps for progress, a compare-and-set stream claim, harness sessions, tool approvals and policies, pending inputs, cited sources, feedback, hashed share links, a model catalog per plan, moderation events and private Realtime topics per chat and per user.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Projects group chats and carry instructions and a default model.
create table if not exists "better_supabase"."ai_projects" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid not null references auth.users (id) on delete cascade,
  "name" text not null check (length("name") between 1 and 200),
  "instructions" text not null default '' check (length("instructions") <= 20000),
  "default_model" text check (length("default_model") <= 200),
  "pinned" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists ai_projects_owner_idx on "better_supabase"."ai_projects" ("owner_id", "organization_id");
alter table "better_supabase"."ai_projects" enable row level security;
revoke all on "better_supabase"."ai_projects" from anon, authenticated;
grant all on "better_supabase"."ai_projects" to service_role;
grant select on "better_supabase"."ai_projects" to authenticated;
drop policy if exists ai_projects_owner_read on "better_supabase"."ai_projects";
create policy ai_projects_owner_read on "better_supabase"."ai_projects" for select to authenticated
  using ("owner_id" = (select auth.uid()));

-- One row per conversation. current_leaf_id is the message the chat shows;
-- active_stream_id is the reply being written, claimed compare-and-set.
create table if not exists "better_supabase"."ai_chats" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid not null references auth.users (id) on delete cascade,
  "project_id" uuid references "better_supabase"."ai_projects" ("id") on delete set null,
  "agent_id" text check (length("agent_id") <= 200),
  "title" text not null default '' check (length("title") <= 300),
  "model" text check (length("model") <= 200),
  "visibility" text not null default 'private' check ("visibility" in ('private', 'organization')),
  "pinned" boolean not null default false,
  "archived_at" timestamptz,
  "is_temporary" boolean not null default false,
  "expires_at" timestamptz,
  "current_leaf_id" text,
  "active_stream_id" text,
  "active_run_id" uuid,
  "last_message_at" timestamptz not null default clock_timestamp(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "search_tsv" tsvector generated always as (to_tsvector('simple'::regconfig, "title")) stored,
  check (not "is_temporary" or "expires_at" is not null)
);
create index if not exists ai_chats_owner_idx on "better_supabase"."ai_chats" ("owner_id", "last_message_at" desc, "id" desc);
create index if not exists ai_chats_tenant_idx on "better_supabase"."ai_chats" ("organization_id");
create index if not exists ai_chats_project_idx on "better_supabase"."ai_chats" ("project_id");
create index if not exists ai_chats_expires_idx on "better_supabase"."ai_chats" ("expires_at") where "is_temporary";
create index if not exists ai_chats_search_idx on "better_supabase"."ai_chats" using gin ("search_tsv");
alter table "better_supabase"."ai_chats" enable row level security;
revoke all on "better_supabase"."ai_chats" from anon, authenticated;
grant all on "better_supabase"."ai_chats" to service_role;
grant select on "better_supabase"."ai_chats" to authenticated;
drop policy if exists ai_chats_read on "better_supabase"."ai_chats";
create policy ai_chats_read on "better_supabase"."ai_chats" for select to authenticated
  using (
    "owner_id" = (select auth.uid())
    or ("visibility" = 'organization' and "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read')))
  );

-- The message tree: (chat_id, id) is the key, parent_id the previous turn.
-- Editing a prompt or regenerating a reply adds a sibling, never an update.
-- parts holds the canonical AI message parts; native the SDK's own shape.
create table if not exists "better_supabase"."ai_messages" (
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "id" text not null check (length("id") between 1 and 200),
  "parent_id" text,
  "owner_id" uuid not null,
  "role" text not null check ("role" in ('system', 'user', 'assistant', 'tool')),
  "parts" jsonb not null default '[]' check (
    jsonb_typeof("parts") = 'array'
    and not jsonb_path_exists("parts", '$[*] ? (!(@.type == "text" || @.type == "reasoning" || @.type == "file" || @.type == "tool-call" || @.type == "tool-result" || @.type == "tool-approval" || @.type == "source" || @.type == "data" || @.type == "step"))')
  ),
  "format" text not null default 'canonical' check (length("format") between 1 and 50),
  "native" jsonb,
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "model" text,
  "status" text not null default 'complete' check ("status" in ('complete', 'aborted', 'error')),
  "seq" bigint generated always as identity,
  "created_at" timestamptz not null default now(),
  "search_tsv" tsvector generated always as (to_tsvector('simple'::regconfig, jsonb_path_query_array("parts", '$[*] ? (@.type == "text").text'))) stored,
  primary key ("chat_id", "id"),
  foreign key ("chat_id", "parent_id") references "better_supabase"."ai_messages" ("chat_id", "id") on delete cascade
);
create index if not exists ai_messages_parent_idx on "better_supabase"."ai_messages" ("chat_id", "parent_id");
create index if not exists ai_messages_owner_idx on "better_supabase"."ai_messages" ("owner_id");
create index if not exists ai_messages_search_idx on "better_supabase"."ai_messages" using gin ("search_tsv");
alter table "better_supabase"."ai_messages" enable row level security;
revoke all on "better_supabase"."ai_messages" from anon, authenticated;
grant all on "better_supabase"."ai_messages" to service_role;
grant select on "better_supabase"."ai_messages" to authenticated;
drop policy if exists ai_messages_read on "better_supabase"."ai_messages";
create policy ai_messages_read on "better_supabase"."ai_messages" for select to authenticated
  using ("chat_id" in (select x."id" from "better_supabase"."ai_chats" x));

-- One generation: the stream it wrote, its usage and cost.
create table if not exists "better_supabase"."ai_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "owner_id" uuid not null,
  "assistant_message_id" text,
  "stream_id" text,
  "engine" text not null default 'ai-sdk' check (length("engine") between 1 and 50),
  "external_run_id" text check (length("external_run_id") <= 200),
  "model" text,
  "status" text not null default 'running' check ("status" in ('queued', 'running', 'cancel_requested', 'completed', 'failed', 'cancelled')),
  "provider_generation_id" text,
  "usage" jsonb not null default '{}' check (jsonb_typeof("usage") = 'object'),
  "cost_micro_usd" bigint check ("cost_micro_usd" >= 0),
  "error" text,
  "started_at" timestamptz not null default now(),
  "ended_at" timestamptz
);
create index if not exists ai_runs_chat_idx on "better_supabase"."ai_runs" ("chat_id", "started_at" desc);
create index if not exists ai_runs_owner_idx on "better_supabase"."ai_runs" ("owner_id");
create index if not exists ai_runs_generation_idx on "better_supabase"."ai_runs" ("provider_generation_id") where "provider_generation_id" is not null;
create index if not exists ai_runs_external_idx on "better_supabase"."ai_runs" ("engine", "external_run_id") where "external_run_id" is not null;
alter table "better_supabase"."ai_runs" enable row level security;
revoke all on "better_supabase"."ai_runs" from anon, authenticated;
grant all on "better_supabase"."ai_runs" to service_role;
grant select on "better_supabase"."ai_runs" to authenticated;
drop policy if exists ai_runs_owner_read on "better_supabase"."ai_runs";
create policy ai_runs_owner_read on "better_supabase"."ai_runs" for select to authenticated
  using ("owner_id" = (select auth.uid()));

-- Tool calls that wait for a person: requested by the server, decided once.
create table if not exists "better_supabase"."ai_tool_approvals" (
  "approval_id" text primary key check (length("approval_id") between 1 and 200),
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "owner_id" uuid not null,
  "run_id" uuid references "better_supabase"."ai_runs" ("id") on delete set null,
  "message_id" text,
  "tool" text not null check (length("tool") between 1 and 200),
  "tool_call_id" text not null,
  "input" jsonb,
  "decision" text check ("decision" in ('approved', 'denied')),
  "reason" text check (length("reason") <= 2000),
  "signature" text,
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists ai_tool_approvals_chat_idx on "better_supabase"."ai_tool_approvals" ("chat_id");
create index if not exists ai_tool_approvals_run_idx on "better_supabase"."ai_tool_approvals" ("run_id");
create index if not exists ai_tool_approvals_owner_idx on "better_supabase"."ai_tool_approvals" ("owner_id");
alter table "better_supabase"."ai_tool_approvals" enable row level security;
revoke all on "better_supabase"."ai_tool_approvals" from anon, authenticated;
grant all on "better_supabase"."ai_tool_approvals" to service_role;
grant select on "better_supabase"."ai_tool_approvals" to authenticated;
drop policy if exists ai_tool_approvals_owner_read on "better_supabase"."ai_tool_approvals";
create policy ai_tool_approvals_owner_read on "better_supabase"."ai_tool_approvals" for select to authenticated
  using ("owner_id" = (select auth.uid()));

-- Per tenant: whether a tool runs (auto), waits for approval (ask) or never
-- runs (deny).
create table if not exists "better_supabase"."ai_tool_policies" (
  "organization_id" uuid not null,
  "tool" text not null check (length("tool") between 1 and 200),
  "policy" text not null check ("policy" in ('auto', 'ask', 'deny')),
  "updated_at" timestamptz not null default now(),
  primary key ("organization_id", "tool")
);
alter table "better_supabase"."ai_tool_policies" enable row level security;
revoke all on "better_supabase"."ai_tool_policies" from anon, authenticated;
grant all on "better_supabase"."ai_tool_policies" to service_role;

-- A question the model asked the user mid-run (a form or a choice).
create table if not exists "better_supabase"."ai_pending_inputs" (
  "id" uuid primary key default gen_random_uuid(),
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "owner_id" uuid not null,
  "run_id" uuid references "better_supabase"."ai_runs" ("id") on delete set null,
  "tool_call_id" text,
  "question" text not null check (length("question") between 1 and 2000),
  "schema" jsonb,
  "answer" jsonb,
  "answered_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists ai_pending_inputs_chat_idx on "better_supabase"."ai_pending_inputs" ("chat_id");
create index if not exists ai_pending_inputs_run_idx on "better_supabase"."ai_pending_inputs" ("run_id");
create index if not exists ai_pending_inputs_owner_idx on "better_supabase"."ai_pending_inputs" ("owner_id");
alter table "better_supabase"."ai_pending_inputs" enable row level security;
revoke all on "better_supabase"."ai_pending_inputs" from anon, authenticated;
grant all on "better_supabase"."ai_pending_inputs" to service_role;
grant select on "better_supabase"."ai_pending_inputs" to authenticated;
drop policy if exists ai_pending_inputs_owner_read on "better_supabase"."ai_pending_inputs";
create policy ai_pending_inputs_owner_read on "better_supabase"."ai_pending_inputs" for select to authenticated
  using ("owner_id" = (select auth.uid()));

-- The sources a reply cited, copied out of its parts when it is saved.
create table if not exists "better_supabase"."ai_message_sources" (
  "chat_id" uuid not null,
  "message_id" text not null,
  "source_id" text not null,
  "source_type" text not null default 'url' check ("source_type" in ('url', 'document')),
  "url" text,
  "title" text,
  "provider_metadata" jsonb,
  primary key ("chat_id", "message_id", "source_id"),
  foreign key ("chat_id", "message_id") references "better_supabase"."ai_messages" ("chat_id", "id") on delete cascade
);
alter table "better_supabase"."ai_message_sources" enable row level security;
revoke all on "better_supabase"."ai_message_sources" from anon, authenticated;
grant all on "better_supabase"."ai_message_sources" to service_role;
grant select on "better_supabase"."ai_message_sources" to authenticated;
drop policy if exists ai_message_sources_read on "better_supabase"."ai_message_sources";
create policy ai_message_sources_read on "better_supabase"."ai_message_sources" for select to authenticated
  using ("chat_id" in (select x."id" from "better_supabase"."ai_chats" x));

-- Thumbs up (1) or down (-1) on a reply, one per user.
create table if not exists "better_supabase"."ai_message_feedback" (
  "chat_id" uuid not null,
  "message_id" text not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "rating" smallint not null check ("rating" in (-1, 1)),
  "reason" text check (length("reason") <= 200),
  "comment" text check (length("comment") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("chat_id", "message_id", "user_id"),
  foreign key ("chat_id", "message_id") references "better_supabase"."ai_messages" ("chat_id", "id") on delete cascade
);
create index if not exists ai_message_feedback_user_idx on "better_supabase"."ai_message_feedback" ("user_id");
alter table "better_supabase"."ai_message_feedback" enable row level security;
revoke all on "better_supabase"."ai_message_feedback" from anon, authenticated;
grant all on "better_supabase"."ai_message_feedback" to service_role;
grant select on "better_supabase"."ai_message_feedback" to authenticated;
drop policy if exists ai_message_feedback_own_read on "better_supabase"."ai_message_feedback";
create policy ai_message_feedback_own_read on "better_supabase"."ai_message_feedback" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- A read-only link to one branch of a chat. Only the SHA-256 of the token is
-- stored; the token is returned once.
create table if not exists "better_supabase"."ai_chat_shares" (
  "id" uuid primary key default gen_random_uuid(),
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "token_hash" text not null unique check ("token_hash" ~ '^[0-9a-f]{64}$'),
  "leaf_id" text not null,
  "created_by" uuid not null references auth.users (id) on delete cascade,
  "created_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create index if not exists ai_chat_shares_chat_idx on "better_supabase"."ai_chat_shares" ("chat_id");
create index if not exists ai_chat_shares_created_by_idx on "better_supabase"."ai_chat_shares" ("created_by");
alter table "better_supabase"."ai_chat_shares" enable row level security;
revoke all on "better_supabase"."ai_chat_shares" from anon, authenticated;
grant all on "better_supabase"."ai_chat_shares" to service_role;

-- The models a tenant may pick, refreshed from the gateway. plans limits a
-- model to tenants with one of those entitlements; empty means everyone.
create table if not exists "better_supabase"."ai_model_catalog" (
  "model_id" text primary key check (length("model_id") between 1 and 200),
  "provider" text not null default '',
  "name" text not null default '',
  "pricing" jsonb not null default '{}',
  "capabilities" jsonb not null default '{}',
  "plans" text[] not null default '{}',
  "enabled" boolean not null default true,
  "refreshed_at" timestamptz not null default now()
);
alter table "better_supabase"."ai_model_catalog" enable row level security;
revoke all on "better_supabase"."ai_model_catalog" from anon, authenticated;
grant all on "better_supabase"."ai_model_catalog" to service_role;

-- What moderation decided about an input, an output or a tool call.
create table if not exists "better_supabase"."ai_moderation_events" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "chat_id" uuid references "better_supabase"."ai_chats" ("id") on delete set null,
  "message_id" text,
  "user_id" uuid references auth.users (id) on delete set null,
  "stage" text not null check ("stage" in ('input', 'output', 'tool')),
  "category" text not null check (length("category") between 1 and 100),
  "score" real,
  "action" text not null check ("action" in ('allow', 'flag', 'redact', 'block')),
  "created_at" timestamptz not null default now()
);
create index if not exists ai_moderation_events_tenant_idx on "better_supabase"."ai_moderation_events" ("organization_id", "created_at" desc);
create index if not exists ai_moderation_events_chat_idx on "better_supabase"."ai_moderation_events" ("chat_id");
create index if not exists ai_moderation_events_user_idx on "better_supabase"."ai_moderation_events" ("user_id");
alter table "better_supabase"."ai_moderation_events" enable row level security;
revoke all on "better_supabase"."ai_moderation_events" from anon, authenticated;
grant all on "better_supabase"."ai_moderation_events" to service_role;

-- The progress of a long run, one row per step key, so a reload shows it.
create table if not exists "better_supabase"."ai_run_steps" (
  "id" uuid primary key default gen_random_uuid(),
  "run_id" uuid not null references "better_supabase"."ai_runs" ("id") on delete cascade,
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "owner_id" uuid not null,
  "step_key" text not null check (length("step_key") between 1 and 200),
  "label" text not null check (length("label") between 1 and 300),
  "status" text not null default 'running' check ("status" in ('running', 'done', 'error', 'skipped')),
  "detail" jsonb not null default '{}' check (jsonb_typeof("detail") = 'object'),
  "started_at" timestamptz not null default now(),
  "ended_at" timestamptz,
  unique ("run_id", "step_key")
);
create index if not exists ai_run_steps_chat_idx on "better_supabase"."ai_run_steps" ("chat_id");
create index if not exists ai_run_steps_owner_idx on "better_supabase"."ai_run_steps" ("owner_id");
alter table "better_supabase"."ai_run_steps" enable row level security;
revoke all on "better_supabase"."ai_run_steps" from anon, authenticated;
grant all on "better_supabase"."ai_run_steps" to service_role;
grant select on "better_supabase"."ai_run_steps" to authenticated;
drop policy if exists ai_run_steps_owner_read on "better_supabase"."ai_run_steps";
create policy ai_run_steps_owner_read on "better_supabase"."ai_run_steps" for select to authenticated
  using ("owner_id" = (select auth.uid()));

-- What a coding-agent harness needs to pick up a chat again: its resume and
-- continue state; its sandbox is a row in ai_sandboxes. lock_holder and locked_until
-- keep two turns from driving one sandbox. Experimental.
create table if not exists "better_supabase"."ai_harness_sessions" (
  "chat_id" uuid not null references "better_supabase"."ai_chats" ("id") on delete cascade,
  "harness_id" text not null check (length("harness_id") between 1 and 200),
  "owner_id" uuid not null,
  "resume_state" jsonb,
  "continue_state" jsonb,
  "status" text not null default 'active' check ("status" in ('active', 'idle', 'stopped', 'error')),
  "lock_holder" text check (length("lock_holder") <= 200),
  "locked_until" timestamptz,
  "last_active_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("chat_id", "harness_id")
);
create index if not exists ai_harness_sessions_owner_idx on "better_supabase"."ai_harness_sessions" ("owner_id");
create index if not exists ai_harness_sessions_idle_idx on "better_supabase"."ai_harness_sessions" ("last_active_at") where "status" = 'active';
alter table "better_supabase"."ai_harness_sessions" enable row level security;
revoke all on "better_supabase"."ai_harness_sessions" from anon, authenticated;
grant all on "better_supabase"."ai_harness_sessions" to service_role;
-- Resume state can carry harness credentials and sandbox ids, so only the
-- service role reads it, through load_ai_harness_session.
drop policy if exists ai_harness_sessions_owner_read on "better_supabase"."ai_harness_sessions";

-- Whether the caller may read a chat: its owner, the service role, or a
-- member with 'ai_chat.read' when the chat is shared with the organization.
create or replace function "better_supabase"."ai_chat_can_read"(chat uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."ai_chats" x
    where x."id" = ai_chat_can_read.chat
      and (
        coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
        or x."owner_id" = (select auth.uid())
        or (x."visibility" = 'organization' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai_chat.read'), false))
      )
  );
$$;
revoke execute on function "better_supabase"."ai_chat_can_read"(uuid) from public, anon;
grant execute on function "better_supabase"."ai_chat_can_read"(uuid) to authenticated, service_role;

-- Sends a payload-free event to a chat's topic and, with list, to its
-- owner's sidebar topic.
create or replace function "better_supabase"."ai_chat_notify"(chat uuid, owner uuid, event text, payload jsonb, list boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := coalesce(payload, '{}'::jsonb) || jsonb_build_object('chatId', chat);
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return;
  end if;
  perform realtime.send(v_payload, event, 'ai-chat:' || chat::text, true);
  if list and owner is not null then
    perform realtime.send(v_payload, event, 'ai-chats:' || owner::text, true);
  end if;
end;
$$;
revoke execute on function "better_supabase"."ai_chat_notify"(uuid, uuid, text, jsonb, boolean) from public, anon, authenticated;

-- Creates a chat for the caller in a tenant ('ai_chat.create'). fields may set
-- id (a client-generated uuid, so a retry returns the same chat), title,
-- model, project_id, agent_id, visibility and is_temporary; the service
-- role also sets owner_id. Temporary chats expire after
-- 1 day and stay out of the sidebar.
create or replace function "better_supabase"."create_ai_chat"(tenant uuid, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(create_ai_chat.fields, '{}'::jsonb);
  v_owner uuid := auth.uid();
  v_row "better_supabase"."ai_chats";
  v_id uuid;
  v_project uuid := (v_fields ->> 'project_id')::uuid;
  v_temporary boolean := coalesce((v_fields ->> 'is_temporary')::boolean, false);
  v_visibility text := coalesce(v_fields ->> 'visibility', 'private');
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_owner := coalesce((v_fields ->> 'owner_id')::uuid, v_owner);
  elsif not coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.create'), false) then
    raise exception 'You may not start chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_owner is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_visibility = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_id := coalesce((v_fields ->> 'id')::uuid, gen_random_uuid());
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = v_id;
  if found then
    if v_row."owner_id" <> v_owner then
      raise exception 'Chat % exists', v_id using errcode = '23505', hint = 'AI_CHAT_EXISTS';
    end if;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_owner and pr."organization_id" = create_ai_chat.tenant) then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chats" ("id", "organization_id", "owner_id", "project_id", "agent_id", "title", "model", "visibility", "is_temporary", "expires_at")
  values (
    v_id, create_ai_chat.tenant, v_owner, v_project, v_fields ->> 'agent_id',
    coalesce(v_fields ->> 'title', ''), v_fields ->> 'model', v_visibility, v_temporary,
    case when v_temporary then now() + interval '1 day' end
  )
  returning * into v_row;
  if not v_temporary then
    perform "better_supabase"."ai_chat_notify"(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_ai_chat"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_ai_chat"(uuid, jsonb) to authenticated, service_role;

-- Changes the caller's chat. fields may set title, model, project_id,
-- agent_id, visibility (organization needs 'ai_chat.share'), pinned,
-- archived, and is_temporary = false to keep a temporary chat.
create or replace function "better_supabase"."update_ai_chat"(chat uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(update_ai_chat.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_chats";
  v_project uuid := (v_fields ->> 'project_id')::uuid;
begin
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = update_ai_chat.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', update_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_row."owner_id" and pr."organization_id" = v_row."organization_id") then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row."visibility" <> 'organization'
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_chats" x set
    "title" = case when v_fields ? 'title' then coalesce(v_fields ->> 'title', '') else x."title" end,
    "model" = case when v_fields ? 'model' then v_fields ->> 'model' else x."model" end,
    "project_id" = case when v_fields ? 'project_id' then v_project else x."project_id" end,
    "agent_id" = case when v_fields ? 'agent_id' then v_fields ->> 'agent_id' else x."agent_id" end,
    "visibility" = case when v_fields ? 'visibility' then coalesce(v_fields ->> 'visibility', 'private') else x."visibility" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "is_temporary" = x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true),
    "expires_at" = case when x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true) then x."expires_at" end,
    "updated_at" = now()
  where x."id" = update_ai_chat.chat
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.updated', '{}'::jsonb, not v_row."is_temporary");
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_ai_chat"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_ai_chat"(uuid, jsonb) to authenticated, service_role;

-- Deletes a chat with its messages; its owner, the service role or 'ai_chat.admin'.
create or replace function "better_supabase"."delete_ai_chat"(chat uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_chats";
begin
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'No chat %', delete_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.deleted', '{}'::jsonb, true);
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_chat"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_chat"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_ai_chat"(chat uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_chats";
begin
  if not "better_supabase"."ai_chat_can_read"(get_ai_chat.chat) then
    raise exception 'No chat %', get_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = get_ai_chat.chat;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_ai_chat"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_chat"(uuid) to authenticated, service_role;

-- The caller's chats, newest activity first: { items, next }. Pass next as
-- after for the following page. search matches titles and message text;
-- temporary chats never show.
create or replace function "better_supabase"."list_ai_chats"(tenant uuid default null, search text default null, project uuid default null, pinned boolean default null, archived boolean default false, after text default null, size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_query tsquery;
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(list_ai_chats.size, 50), 1), 200);
  v_items jsonb;
  v_next text;
begin
  if v_uid is null then
    return jsonb_build_object('items', '[]'::jsonb, 'next', null);
  end if;
  if nullif(btrim(list_ai_chats.search), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, list_ai_chats.search);
  end if;
  if list_ai_chats.after is not null then
    v_at := split_part(list_ai_chats.after, '|', 1)::timestamptz;
    v_id := split_part(list_ai_chats.after, '|', 2)::uuid;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', page."id", 'organization_id', page."organization_id", 'owner_id', page."owner_id", 'project_id', page."project_id", 'agent_id', page."agent_id", 'title', page."title", 'model', page."model", 'visibility', page."visibility", 'pinned', page."pinned", 'archived_at', page."archived_at", 'is_temporary', page."is_temporary", 'expires_at', page."expires_at", 'current_leaf_id', page."current_leaf_id", 'active_stream_id', page."active_stream_id", 'active_run_id', page."active_run_id", 'last_message_at', page."last_message_at", 'created_at', page."created_at", 'updated_at', page."updated_at") order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
  into v_items
  from (
    select x.* from "better_supabase"."ai_chats" x
    where x."owner_id" = v_uid
      and not x."is_temporary"
      and (list_ai_chats.tenant is null or x."organization_id" = list_ai_chats.tenant)
      and (list_ai_chats.project is null or x."project_id" = list_ai_chats.project)
      and (list_ai_chats.pinned is null or x."pinned" = list_ai_chats.pinned)
      and (list_ai_chats.archived is null or (x."archived_at" is not null) = list_ai_chats.archived)
      and (v_at is null or (x."last_message_at", x."id") < (v_at, v_id))
      and (
        v_query is null
        or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query)
      )
    order by x."last_message_at" desc, x."id" desc
    limit v_size + 1
  ) page;
  if jsonb_array_length(v_items) > v_size then
    v_items := v_items - v_size;
    v_next := (v_items -> (v_size - 1) ->> 'last_message_at') || '|' || (v_items -> (v_size - 1) ->> 'id');
  end if;
  return jsonb_build_object('items', v_items, 'next', v_next);
end;
$$;
revoke execute on function "better_supabase"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) to authenticated, service_role;

-- Creates a project (id null, needs 'ai_chat.create') or changes the caller's
-- own. fields may set name, instructions, default_model, pinned, archived.
create or replace function "better_supabase"."save_ai_project"(id uuid, tenant uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(save_ai_project.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_projects";
begin
  if save_ai_project.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_ai_project.tenant, 'ai_chat.create'), false) then
      raise exception 'You may not create projects here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_projects" ("organization_id", "owner_id", "name", "instructions", "default_model", "pinned")
    values (
      save_ai_project.tenant, auth.uid(), v_fields ->> 'name', coalesce(v_fields ->> 'instructions', ''),
      v_fields ->> 'default_model', coalesce((v_fields ->> 'pinned')::boolean, false)
    )
    returning * into v_row;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  update "better_supabase"."ai_projects" x set
    "name" = coalesce(v_fields ->> 'name', x."name"),
    "instructions" = case when v_fields ? 'instructions' then coalesce(v_fields ->> 'instructions', '') else x."instructions" end,
    "default_model" = case when v_fields ? 'default_model' then v_fields ->> 'default_model' else x."default_model" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "updated_at" = now()
  where x."id" = save_ai_project.id and x."owner_id" = (select auth.uid())
  returning * into v_row;
  if not found then
    raise exception 'No project %', save_ai_project.id using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_ai_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_ai_project"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes the caller's project; its chats stay, outside any project.
create or replace function "better_supabase"."delete_ai_project"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."ai_projects" x where x."id" = delete_ai_project.id and x."owner_id" = (select auth.uid());
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_project"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_project"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_ai_projects"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."pinned" desc, x."updated_at" desc), '[]'::jsonb)
  from "better_supabase"."ai_projects" x
  where x."owner_id" = (select auth.uid()) and x."organization_id" = list_ai_projects.tenant;
$$;
revoke execute on function "better_supabase"."list_ai_projects"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_projects"(uuid) to authenticated, service_role;

-- The branch that ends at leaf, root first, with each message's place among
-- its siblings (sibling_index of sibling_count) for the "2 / 3" arrows. No
-- permission check: callers check first.
create or replace function "better_supabase"."ai_message_path_of"(chat uuid, leaf text, include_native boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up as (
    select x.*, 0 as depth from "better_supabase"."ai_messages" x
    where x."chat_id" = ai_message_path_of.chat and x."id" = ai_message_path_of.leaf
    union all
    select x.*, up.depth + 1 from "better_supabase"."ai_messages" x
    join up on x."chat_id" = up."chat_id" and x."id" = up."parent_id"
    where up.depth < 10000
  )
  select coalesce(jsonb_agg(
    jsonb_build_object('id', up."id", 'parent_id', up."parent_id", 'role', up."role", 'parts', up."parts", 'metadata', up."metadata", 'format', up."format", 'native', case when ai_message_path_of.include_native then up."native" end, 'model', up."model", 'status', up."status", 'created_at', up."created_at") || jsonb_build_object(
      'sibling_count', (select count(*) from "better_supabase"."ai_messages" sb where sb."chat_id" = up."chat_id" and sb."parent_id" is not distinct from up."parent_id"),
      'sibling_index', (select count(*) from "better_supabase"."ai_messages" sb where sb."chat_id" = up."chat_id" and sb."parent_id" is not distinct from up."parent_id" and sb."seq" < up."seq")
    )
    order by up.depth desc
  ), '[]'::jsonb)
  from up;
$$;
revoke execute on function "better_supabase"."ai_message_path_of"(uuid, text, boolean) from public, anon, authenticated;

-- The branch the chat shows (or the one ending at leaf), root first.
create or replace function "better_supabase"."ai_message_path"(chat uuid, leaf text default null, include_native boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leaf text;
begin
  if not "better_supabase"."ai_chat_can_read"(ai_message_path.chat) then
    raise exception 'No chat %', ai_message_path.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select coalesce(ai_message_path.leaf, x."current_leaf_id") into v_leaf from "better_supabase"."ai_chats" x where x."id" = ai_message_path.chat;
  if v_leaf is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."ai_message_path_of"(ai_message_path.chat, v_leaf, coalesce(ai_message_path.include_native, false));
end;
$$;
revoke execute on function "better_supabase"."ai_message_path"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."ai_message_path"(uuid, text, boolean) to authenticated, service_role;

-- The versions of a message (same parent), oldest first.
create or replace function "better_supabase"."ai_message_siblings"(chat uuid, message_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parent text;
begin
  if not "better_supabase"."ai_chat_can_read"(ai_message_siblings.chat) then
    raise exception 'No chat %', ai_message_siblings.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select x."parent_id" into v_parent from "better_supabase"."ai_messages" x
  where x."chat_id" = ai_message_siblings.chat and x."id" = ai_message_siblings.message_id;
  if not found then
    raise exception 'No message %', ai_message_siblings.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'role', x."role", 'created_at', x."created_at") order by x."seq"), '[]'::jsonb)
    from "better_supabase"."ai_messages" x
    where x."chat_id" = ai_message_siblings.chat and x."parent_id" is not distinct from v_parent
  );
end;
$$;
revoke execute on function "better_supabase"."ai_message_siblings"(uuid, text) from public, anon;
grant execute on function "better_supabase"."ai_message_siblings"(uuid, text) to authenticated, service_role;

-- Shows the branch through message_id: the chat's leaf becomes the newest
-- descendant of message_id, following the latest child at each turn.
create or replace function "better_supabase"."switch_ai_branch"(chat uuid, message_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = switch_ai_branch.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', switch_ai_branch.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = switch_ai_branch.chat and x."id" = switch_ai_branch.message_id) then
    raise exception 'No message %', switch_ai_branch.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  with recursive down as (
    select switch_ai_branch.message_id as id, 0 as depth
    union all
    select (
      select c."id" from "better_supabase"."ai_messages" c
      where c."chat_id" = switch_ai_branch.chat and c."parent_id" = down.id
      order by c."seq" desc limit 1
    ), down.depth + 1
    from down
    where down.id is not null and down.depth < 10000
  )
  select d.id into v_leaf from down d where d.id is not null order by d.depth desc limit 1;
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_leaf, "updated_at" = now() where x."id" = switch_ai_branch.chat;
  perform "better_supabase"."ai_chat_notify"(switch_ai_branch.chat, null, 'leaf.changed', jsonb_build_object('leafId', v_leaf), false);
  return jsonb_build_object('leaf_id', v_leaf);
end;
$$;
revoke execute on function "better_supabase"."switch_ai_branch"(uuid, text) from public, anon;
grant execute on function "better_supabase"."switch_ai_branch"(uuid, text) to authenticated, service_role;

-- Stores the user's message. trigger 'submit-message' appends message under
-- the chat's leaf, or, with message_id, as a new version of that message.
-- The id is the client's, so a retry with the same parts is a no-op; the
-- same id with other parts is an edit and gets a fresh id. trigger
-- 'regenerate-message' stores nothing and moves the leaf to the user
-- message whose reply is regenerated. Returns { message_id, parent_id,
-- created }; the reply goes under message_id (or parent_id on regenerate).
create or replace function "better_supabase"."append_ai_user_message"(chat uuid, message jsonb, trigger text default 'submit-message', message_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_existing "better_supabase"."ai_messages";
  v_id text;
  v_parent text;
  v_target text;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = append_ai_user_message.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', append_ai_user_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if coalesce(append_ai_user_message.trigger, 'submit-message') = 'regenerate-message' then
    v_target := coalesce(append_ai_user_message.message_id, v_chat."current_leaf_id");
    select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_target;
    if not found then
      raise exception 'No message % to regenerate', v_target using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
    v_parent := case when v_existing."role" = 'user' then v_existing."id" else v_existing."parent_id" end;
    update "better_supabase"."ai_chats" x set "current_leaf_id" = v_parent, "updated_at" = now() where x."id" = v_chat."id";
    perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'leaf.changed', jsonb_build_object('leafId', v_parent), false);
    return jsonb_build_object('message_id', v_parent, 'parent_id', v_parent, 'created', false);
  elsif append_ai_user_message.trigger <> 'submit-message' then
    raise exception 'Unknown trigger %', append_ai_user_message.trigger using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if jsonb_typeof(append_ai_user_message.message) is distinct from 'object'
    or append_ai_user_message.message ->> 'role' is distinct from 'user'
    or nullif(append_ai_user_message.message ->> 'id', '') is null
    or jsonb_typeof(append_ai_user_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A user message needs an id, role user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  v_id := append_ai_user_message.message ->> 'id';
  select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_id;
  if found then
    if v_existing."parts" = append_ai_user_message.message -> 'parts' then
      return jsonb_build_object('message_id', v_id, 'parent_id', v_existing."parent_id", 'created', false);
    end if;
    v_parent := v_existing."parent_id";
    v_id := gen_random_uuid()::text;
  elsif append_ai_user_message.message_id is not null then
    select x."parent_id" into v_parent from "better_supabase"."ai_messages" x
    where x."chat_id" = v_chat."id" and x."id" = append_ai_user_message.message_id;
    if not found then
      raise exception 'No message %', append_ai_user_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
  else
    v_parent := v_chat."current_leaf_id";
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata")
  values (
    v_chat."id", v_id, v_parent, v_chat."owner_id", 'user', append_ai_user_message.message -> 'parts',
    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end
  );
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);
end;
$$;
revoke execute on function "better_supabase"."append_ai_user_message"(uuid, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."append_ai_user_message"(uuid, jsonb, text, text) to authenticated, service_role;

-- Stores a reply under parent_id (the service role only): an upsert by id, so
-- the server saves once at the end and again after a resumed stream. Copies
-- source parts to "better_supabase"."ai_message_sources" and moves the leaf to the reply.
create or replace function "better_supabase"."save_ai_assistant_message"(chat uuid, message jsonb, parent_id text, status text default 'complete', model text default null, format text default 'canonical', native jsonb default null, run uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_id text := save_ai_assistant_message.message ->> 'id';
  v_role text := coalesce(save_ai_assistant_message.message ->> 'role', 'assistant');
  v_status text := coalesce(save_ai_assistant_message.status, 'complete');
  v_created boolean;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_assistant_message.chat for update;
  if not found then
    raise exception 'No chat %', save_ai_assistant_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if nullif(v_id, '') is null or v_role = 'user'
    or jsonb_typeof(save_ai_assistant_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A reply needs an id, a role other than user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if save_ai_assistant_message.parent_id is not null and not exists (
    select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = save_ai_assistant_message.parent_id
  ) then
    raise exception 'No message %', save_ai_assistant_message.parent_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata", "format", "native", "model", "status")
  values (
    v_chat."id", v_id, save_ai_assistant_message.parent_id, v_chat."owner_id", v_role,
    save_ai_assistant_message.message -> 'parts',
    case when jsonb_typeof(save_ai_assistant_message.message -> 'metadata') = 'object' then save_ai_assistant_message.message -> 'metadata' else '{}'::jsonb end,
    coalesce(save_ai_assistant_message.format, 'canonical'), save_ai_assistant_message.native,
    save_ai_assistant_message.model, v_status
  )
  on conflict ("chat_id", "id") do update set
    "parts" = excluded."parts",
    "metadata" = excluded."metadata",
    "format" = excluded."format",
    "native" = excluded."native",
    "model" = coalesce(excluded."model", "better_supabase"."ai_messages"."model"),
    "status" = excluded."status"
  returning (xmax = 0) into v_created;
  delete from "better_supabase"."ai_message_sources" x where x."chat_id" = v_chat."id" and x."message_id" = v_id;
  insert into "better_supabase"."ai_message_sources" ("chat_id", "message_id", "source_id", "source_type", "url", "title", "provider_metadata")
  select distinct on (e ->> 'id') v_chat."id", v_id, e ->> 'id', coalesce(e ->> 'sourceType', 'url'), e ->> 'url', e ->> 'title', e -> 'providerMetadata'
  from jsonb_array_elements(save_ai_assistant_message.message -> 'parts') e
  where e ->> 'type' = 'source' and nullif(e ->> 'id', '') is not null and coalesce(e ->> 'sourceType', 'url') in ('url', 'document')
  order by e ->> 'id';
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  if save_ai_assistant_message.run is not null then
    update "better_supabase"."ai_runs" x set "assistant_message_id" = v_id where x."id" = save_ai_assistant_message.run and x."chat_id" = v_chat."id";
  end if;
  if v_status = 'complete' then
    null;
  end if;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', save_ai_assistant_message.parent_id, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) to service_role;

-- Claims the chat for one reply stream (the service role only). A claim
-- held by a run that ended, whose stream closed, or that started more than
-- 10 minutes ago is taken over. Returns { claimed, stream_id,
-- run_id }: the active stream when another reply holds the chat.
-- external_run_id is the durable engine's own run id, such as a Workflow
-- SDK run, so stop and resume can reach that run.
drop function if exists "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text);
create or replace function "better_supabase"."claim_ai_chat_stream"(chat uuid, stream text, model text default null, message_id text default null, engine text default 'ai-sdk', external_run_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_run "better_supabase"."ai_runs";
  v_run_id uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = claim_ai_chat_stream.chat for update;
  if not found then
    raise exception 'No chat %', claim_ai_chat_stream.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is not null then
    select * into v_run from "better_supabase"."ai_runs" x where x."id" = v_chat."active_run_id";
    if v_chat."active_stream_id" = claim_ai_chat_stream.stream then
      return jsonb_build_object('claimed', true, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    if v_run."id" is not null
      and v_run."status" in ('queued', 'running', 'cancel_requested')
      and v_run."started_at" > now() - interval '10 minutes'
      and not exists (
        select 1 from "better_supabase"."streams" so
        where so."id" = v_chat."active_stream_id" and so."closed_at" is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    update "better_supabase"."ai_runs" x set "status" = 'cancelled', "ended_at" = now()
    where x."id" = v_chat."active_run_id" and x."ended_at" is null;
  end if;
  insert into "better_supabase"."ai_runs" ("chat_id", "owner_id", "assistant_message_id", "stream_id", "engine", "external_run_id", "model")
  values (v_chat."id", v_chat."owner_id", claim_ai_chat_stream.message_id, claim_ai_chat_stream.stream, coalesce(claim_ai_chat_stream.engine, 'ai-sdk'), claim_ai_chat_stream.external_run_id, coalesce(claim_ai_chat_stream.model, v_chat."model"))
  returning "id" into v_run_id;
  update "better_supabase"."ai_chats" x set "active_stream_id" = claim_ai_chat_stream.stream, "active_run_id" = v_run_id, "updated_at" = now()
  where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$$;
revoke execute on function "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text, text) to service_role;

-- Ends the claim when the stream finished (the service role only) and
-- records the run's status, usage, gateway generation id and cost.
create or replace function "better_supabase"."release_ai_chat_stream"(chat uuid, stream text, status text default 'completed', usage jsonb default null, generation_id text default null, error text default null, cost_micro_usd bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_status text := coalesce(release_ai_chat_stream.status, 'completed');
  v_found boolean := false;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'A run ends completed, failed or cancelled, not %', v_status using errcode = '22023', hint = 'AI_RUN_INVALID';
  end if;
  update "better_supabase"."ai_runs" x set
    "status" = v_status,
    "usage" = coalesce(release_ai_chat_stream.usage, x."usage"),
    "provider_generation_id" = coalesce(release_ai_chat_stream.generation_id, x."provider_generation_id"),
    "error" = release_ai_chat_stream.error,
    "cost_micro_usd" = coalesce(release_ai_chat_stream.cost_micro_usd, x."cost_micro_usd"),
    "ended_at" = coalesce(x."ended_at", now())
  where x."chat_id" = release_ai_chat_stream.chat and x."stream_id" = release_ai_chat_stream.stream;
  update "better_supabase"."ai_chats" x set "active_stream_id" = null, "active_run_id" = null, "updated_at" = now()
  where x."id" = release_ai_chat_stream.chat and x."active_stream_id" = release_ai_chat_stream.stream
  returning true into v_found;
  if coalesce(v_found, false) then
    perform "better_supabase"."ai_chat_notify"(release_ai_chat_stream.chat, null, 'stream.ended', jsonb_build_object('streamId', release_ai_chat_stream.stream, 'status', v_status), false);
  end if;
  return coalesce(v_found, false);
end;
$$;
revoke execute on function "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) to service_role;

-- Asks the active reply to stop: the run turns cancel_requested and the
-- stream's cancel flag is set, which the writer reads on its next append.
-- Returns { stream_id, run_id }, or null when nothing is streaming.
create or replace function "better_supabase"."request_ai_chat_stop"(chat uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat "better_supabase"."ai_chats";
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = request_ai_chat_stop.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', request_ai_chat_stop.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is null then
    return null;
  end if;
  update "better_supabase"."ai_runs" x set "status" = 'cancel_requested'
  where x."id" = v_chat."active_run_id" and x."status" in ('queued', 'running');
  perform "better_supabase"."stream_cancel"(v_chat."active_stream_id");
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.stopping', jsonb_build_object('streamId', v_chat."active_stream_id"), false);
  return jsonb_build_object('stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
end;
$$;
revoke execute on function "better_supabase"."request_ai_chat_stop"(uuid) from public, anon;
grant execute on function "better_supabase"."request_ai_chat_stop"(uuid) to authenticated, service_role;

-- Records the cost the gateway reported later for a generation id.
create or replace function "better_supabase"."set_ai_run_cost"(generation_id text, cost_micro_usd bigint, usage jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_runs" x set
    "cost_micro_usd" = set_ai_run_cost.cost_micro_usd,
    "usage" = x."usage" || coalesce(set_ai_run_cost.usage, '{}'::jsonb)
  where x."provider_generation_id" = set_ai_run_cost.generation_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."set_ai_run_cost"(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."set_ai_run_cost"(text, bigint, jsonb) to service_role;

-- Records a tool call that waits for approval (the service role only).
-- approval holds approval_id, tool, tool_call_id and optionally input,
-- run_id, message_id and signature. A retry returns the stored row.
create or replace function "better_supabase"."record_ai_tool_approval"(chat uuid, approval jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_tool_approvals";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = record_ai_tool_approval.chat;
  if not found then
    raise exception 'No chat %', record_ai_tool_approval.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_tool_approvals" ("approval_id", "chat_id", "owner_id", "run_id", "message_id", "tool", "tool_call_id", "input", "signature")
  values (
    record_ai_tool_approval.approval ->> 'approval_id', v_chat."id", v_chat."owner_id",
    (record_ai_tool_approval.approval ->> 'run_id')::uuid, record_ai_tool_approval.approval ->> 'message_id',
    record_ai_tool_approval.approval ->> 'tool', record_ai_tool_approval.approval ->> 'tool_call_id',
    record_ai_tool_approval.approval -> 'input', record_ai_tool_approval.approval ->> 'signature'
  )
  on conflict ("approval_id") do nothing;
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = record_ai_tool_approval.approval ->> 'approval_id';
  if v_row."chat_id" <> v_chat."id" then
    raise exception 'Approval % belongs to another chat', v_row."approval_id" using errcode = '23505', hint = 'AI_APPROVAL_EXISTS';
  end if;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'approval.requested', jsonb_build_object('approvalId', v_row."approval_id"), false);
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_ai_tool_approval"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."record_ai_tool_approval"(uuid, jsonb) to service_role;

-- Approves or denies a waiting tool call, once; the service role or the chat's owner.
-- Repeating the same decision returns the row.
create or replace function "better_supabase"."decide_ai_tool_approval"(approval_id text, approved boolean, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
  v_decision text := case when decide_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = decide_ai_tool_approval.approval_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No approval %', decide_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  if decide_ai_tool_approval.approved is null then
    raise exception 'Approve or deny' using errcode = '22023', hint = 'AI_APPROVAL_INVALID';
  end if;
  if v_row."decision" is not null then
    if v_row."decision" = v_decision then
      return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
    end if;
    raise exception 'Approval % was already %', v_row."approval_id", v_row."decision" using errcode = 'P0001', hint = 'AI_APPROVAL_DECIDED';
  end if;
  update "better_supabase"."ai_tool_approvals" x set
    "decision" = v_decision,
    "reason" = decide_ai_tool_approval.reason,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."approval_id" = v_row."approval_id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'approval.decided', jsonb_build_object('approvalId', v_row."approval_id", 'decision', v_decision), false);
  perform better_supabase.audit_event(
    event_type => 'ai_tool_approval.decided',
    category => 'ai',
    target_type => 'ai_tool_approval',
    record_id => v_row."approval_id",
    target_label => v_row."tool",
    tenant => ((select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id"))::uuid,
    metadata => jsonb_build_object('organizationId', (select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id")::text, 'chatId', v_row."chat_id", 'approvalId', v_row."approval_id", 'tool', v_row."tool", 'decision', v_decision),
    idempotency_key => 'ai_tool_approval.decided:' || v_row."approval_id"
  );
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_ai_tool_approval"(text, boolean, text) from public, anon;
grant execute on function "better_supabase"."decide_ai_tool_approval"(text, boolean, text) to authenticated, service_role;

-- A chat's approvals, oldest first; ids narrows them.
create or replace function "better_supabase"."get_ai_tool_approvals"(chat uuid, ids text[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not "better_supabase"."ai_chat_can_read"(get_ai_tool_approvals.chat) then
    raise exception 'No chat %', get_ai_tool_approvals.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('approval_id', x."approval_id", 'chat_id', x."chat_id", 'run_id', x."run_id", 'message_id', x."message_id", 'tool', x."tool", 'tool_call_id', x."tool_call_id", 'input', x."input", 'decision', x."decision", 'reason', x."reason", 'signature', x."signature", 'decided_by', x."decided_by", 'decided_at', x."decided_at", 'created_at', x."created_at") order by x."created_at"), '[]'::jsonb)
    from "better_supabase"."ai_tool_approvals" x
    where x."chat_id" = get_ai_tool_approvals.chat
      and (get_ai_tool_approvals.ids is null or x."approval_id" = any (get_ai_tool_approvals.ids))
  );
end;
$$;
revoke execute on function "better_supabase"."get_ai_tool_approvals"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."get_ai_tool_approvals"(uuid, text[]) to authenticated, service_role;

-- Sets whether a tool runs (auto), asks (ask) or never runs (deny) in a
-- tenant ('ai_chat.admin'); policy null removes the rule.
create or replace function "better_supabase"."set_ai_tool_policy"(tenant uuid, tool text, policy text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_ai_tool_policy.tenant, 'ai_chat.admin'), false)) then
    raise exception 'You may not change tool policies here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if set_ai_tool_policy.policy is null then
    delete from "better_supabase"."ai_tool_policies" x where x."organization_id" = set_ai_tool_policy.tenant and x."tool" = set_ai_tool_policy.tool;
    perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
    return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', null);
  end if;
  insert into "better_supabase"."ai_tool_policies" ("organization_id", "tool", "policy")
  values (set_ai_tool_policy.tenant, set_ai_tool_policy.tool, set_ai_tool_policy.policy)
  on conflict ("organization_id", "tool") do update set "policy" = excluded."policy", "updated_at" = now();
  perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$$;
revoke execute on function "better_supabase"."set_ai_tool_policy"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_ai_tool_policy"(uuid, text, text) to authenticated, service_role;

-- A tenant's tool rules as { tool: policy }, for members ('ai_chat.read').
create or replace function "better_supabase"."ai_tool_policies_for"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', ai_tool_policies_for.tenant, 'ai_chat.read'), false)) then
    return '{}'::jsonb;
  end if;
  return (
    select coalesce(jsonb_object_agg(x."tool", x."policy"), '{}'::jsonb)
    from "better_supabase"."ai_tool_policies" x where x."organization_id" = ai_tool_policies_for.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."ai_tool_policies_for"(uuid) from public, anon;
grant execute on function "better_supabase"."ai_tool_policies_for"(uuid) to authenticated, service_role;

-- Records a question for the user (the service role only): input holds
-- question and optionally schema (a JSON Schema), run_id and tool_call_id.
create or replace function "better_supabase"."open_ai_pending_input"(chat uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_pending_inputs";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = open_ai_pending_input.chat;
  if not found then
    raise exception 'No chat %', open_ai_pending_input.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_pending_inputs" ("chat_id", "owner_id", "run_id", "tool_call_id", "question", "schema")
  values (
    v_chat."id", v_chat."owner_id", (open_ai_pending_input.input ->> 'run_id')::uuid,
    open_ai_pending_input.input ->> 'tool_call_id', open_ai_pending_input.input ->> 'question',
    open_ai_pending_input.input -> 'schema'
  )
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'input.requested', jsonb_build_object('inputId', v_row."id"), false);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'tool_call_id', v_row."tool_call_id", 'question', v_row."question", 'schema', v_row."schema", 'answer', v_row."answer", 'answered_at', v_row."answered_at", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."open_ai_pending_input"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."open_ai_pending_input"(uuid, jsonb) to service_role;

-- Answers a question once; the chat's owner or the service role.
create or replace function "better_supabase"."answer_ai_pending_input"(id uuid, answer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_pending_inputs";
begin
  select * into v_row from "better_supabase"."ai_pending_inputs" x where x."id" = answer_ai_pending_input.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No question %', answer_ai_pending_input.id using errcode = 'P0002', hint = 'AI_INPUT_NOT_FOUND';
  end if;
  if v_row."answered_at" is not null then
    raise exception 'Question % was answered', answer_ai_pending_input.id using errcode = 'P0001', hint = 'AI_INPUT_ANSWERED';
  end if;
  update "better_supabase"."ai_pending_inputs" x set "answer" = coalesce(answer_ai_pending_input.answer, 'null'::jsonb), "answered_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'input.answered', jsonb_build_object('inputId', v_row."id"), false);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'tool_call_id', v_row."tool_call_id", 'question', v_row."question", 'schema', v_row."schema", 'answer', v_row."answer", 'answered_at', v_row."answered_at", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."answer_ai_pending_input"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."answer_ai_pending_input"(uuid, jsonb) to authenticated, service_role;

-- Rates a reply: 1 or -1, with an optional reason and comment; rating null
-- removes the caller's rating. Anyone who can read the chat may rate.
create or replace function "better_supabase"."rate_ai_message"(chat uuid, message_id text, rating integer, reason text default null, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not "better_supabase"."ai_chat_can_read"(rate_ai_message.chat) then
    raise exception 'No chat %', rate_ai_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = rate_ai_message.chat and x."id" = rate_ai_message.message_id) then
    raise exception 'No message %', rate_ai_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  if rate_ai_message.rating is null then
    delete from "better_supabase"."ai_message_feedback" x
    where x."chat_id" = rate_ai_message.chat and x."message_id" = rate_ai_message.message_id and x."user_id" = auth.uid();
    return null;
  end if;
  insert into "better_supabase"."ai_message_feedback" ("chat_id", "message_id", "user_id", "rating", "reason", "comment")
  values (rate_ai_message.chat, rate_ai_message.message_id, auth.uid(), rate_ai_message.rating, rate_ai_message.reason, rate_ai_message.comment)
  on conflict ("chat_id", "message_id", "user_id") do update set
    "rating" = excluded."rating", "reason" = excluded."reason", "comment" = excluded."comment", "updated_at" = now();
  return jsonb_build_object('chat_id', rate_ai_message.chat, 'message_id', rate_ai_message.message_id, 'rating', rate_ai_message.rating, 'reason', rate_ai_message.reason, 'comment', rate_ai_message.comment);
end;
$$;
revoke execute on function "better_supabase"."rate_ai_message"(uuid, text, integer, text, text) from public, anon;
grant execute on function "better_supabase"."rate_ai_message"(uuid, text, integer, text, text) to authenticated, service_role;

-- Creates a read-only link to the branch ending at leaf (default: the one
-- the chat shows); the owner with 'ai_chat.share'. The token is returned once
-- and only its SHA-256 is stored.
create or replace function "better_supabase"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_id uuid;
  v_created timestamptz;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = share_ai_chat.chat;
  if not found or v_chat."owner_id" is distinct from auth.uid() then
    raise exception 'No chat %', share_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.can('tenant', v_chat."organization_id", 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_chat."current_leaf_id");
  if v_leaf is null or not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_leaf) then
    raise exception 'Nothing to share yet' using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chat_shares" ("chat_id", "token_hash", "leaf_id", "created_by")
  values (v_chat."id", encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_leaf, auth.uid())
  returning "id", "created_at" into v_id, v_created;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.shared',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => v_id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', v_id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id", 'leafId', v_leaf),
    idempotency_key => 'ai_chat.shared:' || v_id::text
  );
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf, 'created_at', v_created);
end;
$$;
revoke execute on function "better_supabase"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "better_supabase"."share_ai_chat"(uuid, text) to authenticated, service_role;

-- Revokes a link; whoever made it, the chat's owner or the service role.
create or replace function "better_supabase"."revoke_ai_chat_share"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat_id uuid;
  v_chat "better_supabase"."ai_chats";
begin
  update "better_supabase"."ai_chat_shares" x set "revoked_at" = now()
  where x."id" = revoke_ai_chat_share.id
    and x."revoked_at" is null
    and (
      coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or x."created_by" = (select auth.uid())
      or exists (select 1 from "better_supabase"."ai_chats" c where c."id" = x."chat_id" and c."owner_id" = (select auth.uid()))
    )
  returning x."chat_id" into v_chat_id;
  if v_chat_id is null then
    return false;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" c where c."id" = v_chat_id;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.share_revoked',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => revoke_ai_chat_share.id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', revoke_ai_chat_share.id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_ai_chat_share"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_ai_chat_share"(uuid) to authenticated, service_role;

-- A chat's links, newest first, without their tokens.
create or replace function "better_supabase"."list_ai_chat_shares"(chat uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id", 'leaf_id', x."leaf_id", 'created_by', x."created_by",
    'created_at', x."created_at", 'revoked_at', x."revoked_at"
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."ai_chat_shares" x
  join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
  where x."chat_id" = list_ai_chat_shares.chat
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or c."owner_id" = (select auth.uid()));
$$;
revoke execute on function "better_supabase"."list_ai_chat_shares"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_chat_shares"(uuid) to authenticated, service_role;

-- The shared branch for a link token, for anyone holding it: { chat,
-- leaf_id, messages }, or null when the link is unknown or revoked.
create or replace function "better_supabase"."get_shared_ai_chat"(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_share "better_supabase"."ai_chat_shares";
  v_chat "better_supabase"."ai_chats";
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_share from "better_supabase"."ai_chat_shares" x
  where x."token_hash" = encode(sha256(convert_to(get_shared_ai_chat.token, 'UTF8')), 'hex') and x."revoked_at" is null;
  if not found then
    return null;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = v_share."chat_id";
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat."id", 'title', v_chat."title", 'model', v_chat."model", 'created_at', v_chat."created_at"),
    'leaf_id', v_share."leaf_id",
    'messages', "better_supabase"."ai_message_path_of"(v_chat."id", v_share."leaf_id", false)
  );
end;
$$;
revoke execute on function "better_supabase"."get_shared_ai_chat"(text) from public;
grant execute on function "better_supabase"."get_shared_ai_chat"(text) to anon, authenticated, service_role;

-- Upserts models from the gateway (the service role only): models is an
-- array, or an object whose models key holds one. Each element holds id, and optionally provider, name, pricing, capabilities, plans and
-- enabled. prune deletes the models missing from the list.
create or replace function "better_supabase"."upsert_ai_models"(models jsonb, prune boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_models jsonb := case jsonb_typeof(upsert_ai_models.models)
    when 'array' then upsert_ai_models.models
    when 'object' then coalesce(upsert_ai_models.models -> 'models', '[]'::jsonb)
    else '[]'::jsonb
  end;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_model_catalog" ("model_id", "provider", "name", "pricing", "capabilities", "plans", "enabled")
  select
    e ->> 'id',
    coalesce(e ->> 'provider', split_part(e ->> 'id', '/', 1)),
    coalesce(e ->> 'name', e ->> 'id'),
    coalesce(e -> 'pricing', '{}'::jsonb),
    coalesce(e -> 'capabilities', '{}'::jsonb),
    coalesce(array(select jsonb_array_elements_text(e -> 'plans')), '{}'::text[]),
    coalesce((e ->> 'enabled')::boolean, true)
  from jsonb_array_elements(v_models) e
  where nullif(e ->> 'id', '') is not null
  on conflict ("model_id") do update set
    "provider" = excluded."provider",
    "name" = excluded."name",
    "pricing" = excluded."pricing",
    "capabilities" = excluded."capabilities",
    "refreshed_at" = now();
  get diagnostics v_count = row_count;
  if upsert_ai_models.prune then
    delete from "better_supabase"."ai_model_catalog" x
    where x."model_id" not in (select e ->> 'id' from jsonb_array_elements(v_models) e where e ->> 'id' is not null);
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."upsert_ai_models"(jsonb, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_ai_models"(jsonb, boolean) to service_role;

-- The models a tenant may pick: enabled ones with no plans, and, with the
-- entitlements module, those whose plans the tenant holds.
create or replace function "better_supabase"."allowed_ai_models"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := allowed_ai_models.tenant;
begin
  if v_tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'ai_chat.read'), false)) then
    v_tenant := null;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('model_id', x."model_id", 'provider', x."provider", 'name', x."name", 'pricing', x."pricing", 'capabilities', x."capabilities", 'plans', to_jsonb(x."plans"), 'enabled', x."enabled", 'refreshed_at', x."refreshed_at") order by x."provider", x."name"), '[]'::jsonb)
    from "better_supabase"."ai_model_catalog" x
    where x."enabled" and (cardinality(x."plans") = 0 or (v_tenant is not null and x."plans" && better_supabase.tenant_entitlements(v_tenant)))
  );
end;
$$;
revoke execute on function "better_supabase"."allowed_ai_models"(uuid) from public, anon;
grant execute on function "better_supabase"."allowed_ai_models"(uuid) to authenticated, service_role;

-- Records a moderation decision (the service role only): event holds
-- organization_id, stage, category, action and optionally chat_id,
-- message_id, user_id and score.
create or replace function "better_supabase"."record_ai_moderation_event"(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_moderation_events";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_moderation_events" ("organization_id", "chat_id", "message_id", "user_id", "stage", "category", "score", "action")
  values (
    (record_ai_moderation_event.event ->> 'organization_id')::uuid,
    (record_ai_moderation_event.event ->> 'chat_id')::uuid,
    record_ai_moderation_event.event ->> 'message_id',
    (record_ai_moderation_event.event ->> 'user_id')::uuid,
    record_ai_moderation_event.event ->> 'stage',
    record_ai_moderation_event.event ->> 'category',
    (record_ai_moderation_event.event ->> 'score')::real,
    record_ai_moderation_event.event ->> 'action'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'chat_id', v_row."chat_id", 'message_id', v_row."message_id", 'user_id', v_row."user_id", 'stage', v_row."stage", 'category', v_row."category", 'score', v_row."score", 'action', v_row."action", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_ai_moderation_event"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."record_ai_moderation_event"(jsonb) to service_role;

-- A tenant's moderation decisions, newest first ('ai_chat.moderate').
create or replace function "better_supabase"."list_ai_moderation_events"(tenant uuid, size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_ai_moderation_events.tenant, 'ai_chat.moderate'), false)) then
    raise exception 'You may not review moderation here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', page."id", 'organization_id', page."organization_id", 'chat_id', page."chat_id", 'message_id', page."message_id", 'user_id', page."user_id", 'stage', page."stage", 'category', page."category", 'score', page."score", 'action', page."action", 'created_at', page."created_at") order by page."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."ai_moderation_events" x
      where x."organization_id" = list_ai_moderation_events.tenant
      order by x."created_at" desc
      limit least(greatest(coalesce(list_ai_moderation_events.size, 100), 1), 1000)
    ) page
  );
end;
$$;
revoke execute on function "better_supabase"."list_ai_moderation_events"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_moderation_events"(uuid, integer) to authenticated, service_role;

-- Deletes expired temporary chats, at most batch per call.
create or replace function "better_supabase"."purge_ai_chats"(batch integer default 1000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  with doomed as (
    select x."id" from "better_supabase"."ai_chats" x
    where x."is_temporary" and x."expires_at" <= now()
    limit greatest(coalesce(purge_ai_chats.batch, 1000), 1)
  )
  delete from "better_supabase"."ai_chats" c using doomed where c."id" = doomed."id";
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_ai_chats"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_ai_chats"(integer) to service_role;

-- Sandboxes and provider containers a chat started, harness sessions'
-- included, so one idle-stop claim stops the ones nobody used for
-- idle_seconds or past expires_at.
create table if not exists "better_supabase"."ai_sandboxes" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "harness_id" text check (length("harness_id") between 1 and 200),
  "provider" text not null check ("provider" ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  "sandbox_id" text not null check (length("sandbox_id") between 1 and 200),
  "container_id" text check (length("container_id") <= 200),
  "status" text not null default 'running' check ("status" in ('running', 'stopping', 'stopped')),
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "idle_seconds" integer not null default 600 check ("idle_seconds" > 0),
  "error" text check (length("error") <= 4000),
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz,
  "stopped_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("provider", "sandbox_id")
);
create index if not exists ai_sandboxes_open_idx on "better_supabase"."ai_sandboxes" ("last_used_at") where "status" <> 'stopped';
create index if not exists ai_sandboxes_chat_idx on "better_supabase"."ai_sandboxes" ("chat_id");
create index if not exists ai_sandboxes_harness_idx on "better_supabase"."ai_sandboxes" ("chat_id", "harness_id") where "harness_id" is not null;
create index if not exists ai_sandboxes_tenant_idx on "better_supabase"."ai_sandboxes" ("organization_id");
create index if not exists ai_sandboxes_user_idx on "better_supabase"."ai_sandboxes" ("user_id");
alter table "better_supabase"."ai_sandboxes" enable row level security;
revoke all on "better_supabase"."ai_sandboxes" from anon, authenticated;
grant select on "better_supabase"."ai_sandboxes" to authenticated;
grant all on "better_supabase"."ai_sandboxes" to service_role;
drop policy if exists ai_sandboxes_read on "better_supabase"."ai_sandboxes";
create policy ai_sandboxes_read on "better_supabase"."ai_sandboxes" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')));

-- Records a sandbox or container the app started, or marks a known one used
-- (service role). fields: user_id, chat_id, harness_id, container_id,
-- metadata, idle_seconds, expires_at.
create or replace function "better_supabase"."register_ai_sandbox"(tenant uuid, provider text, sandbox_id text, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
  v_fields jsonb := coalesce(register_ai_sandbox.fields, '{}');
begin
  insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id", "container_id", "metadata", "idle_seconds", "expires_at")
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    v_fields ->> 'harness_id',
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, 600),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict ("provider", "sandbox_id") do update set
    "container_id" = coalesce(excluded."container_id", cur."container_id"),
    "chat_id" = coalesce(excluded."chat_id", cur."chat_id"),
    "harness_id" = coalesce(excluded."harness_id", cur."harness_id"),
    "metadata" = cur."metadata" || excluded."metadata",
    "idle_seconds" = excluded."idle_seconds",
    "expires_at" = coalesce(excluded."expires_at", cur."expires_at"),
    "status" = 'running',
    "error" = null,
    "stopped_at" = null,
    "last_used_at" = now(),
    "updated_at" = now()
  where cur."organization_id" = excluded."organization_id"
  returning * into v_row;
  if not found then
    raise exception 'sandbox % belongs to another tenant', register_ai_sandbox.sandbox_id using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'provider', v_row."provider", 'sandbox_id', v_row."sandbox_id", 'container_id', v_row."container_id", 'status', v_row."status", 'metadata', v_row."metadata", 'idle_seconds', v_row."idle_seconds", 'error', v_row."error", 'last_used_at', v_row."last_used_at", 'expires_at', v_row."expires_at", 'stopped_at', v_row."stopped_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) to service_role;

-- Marks a sandbox used now (service role); false when it is not running.
create or replace function "better_supabase"."touch_ai_sandbox"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."ai_sandboxes" x set "last_used_at" = now(), "updated_at" = now()
  where x."id" = touch_ai_sandbox.id and x."status" = 'running';
  return found;
end;
$$;
revoke execute on function "better_supabase"."touch_ai_sandbox"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."touch_ai_sandbox"(uuid) to service_role;

-- The running sandbox of a chat for a provider, to reuse it (service role).
create or replace function "better_supabase"."ai_sandbox_for"(chat_id uuid, provider text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'harness_id', x."harness_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_sandboxes" x
  where x."chat_id" = ai_sandbox_for.chat_id and x."provider" = ai_sandbox_for.provider and x."status" = 'running'
    and (x."expires_at" is null or x."expires_at" > now())
  order by x."last_used_at" desc
  limit 1
$$;
revoke execute on function "better_supabase"."ai_sandbox_for"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_sandbox_for"(uuid, text) to service_role;

-- Claims sandboxes to stop (service role): running ones idle for
-- idle_seconds or past expires_at, and ones a stopper claimed more than
-- lease_seconds ago without finishing. A sandbox whose harness session a
-- turn holds the lock of is skipped.
create or replace function "better_supabase"."idle_ai_sandboxes"(batch integer default 50, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_sandboxes" y
    where ((y."status" = 'running' and (y."last_used_at" + make_interval(secs => y."idle_seconds") <= now() or y."expires_at" <= now()))
       or (y."status" = 'stopping' and y."updated_at" <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1))))
      and not exists (
        select 1 from "better_supabase"."ai_harness_sessions" z
        where z."chat_id" = y."chat_id" and z."harness_id" = y."harness_id" and z."locked_until" > now()
      )
    order by y."last_used_at"
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_sandboxes" x set "status" = 'stopping', "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'chat_id', claimed."chat_id", 'harness_id', claimed."harness_id", 'provider', claimed."provider", 'sandbox_id', claimed."sandbox_id", 'container_id', claimed."container_id", 'status', claimed."status", 'metadata', claimed."metadata", 'idle_seconds', claimed."idle_seconds", 'error', claimed."error", 'last_used_at', claimed."last_used_at", 'expires_at', claimed."expires_at", 'stopped_at', claimed."stopped_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."idle_ai_sandboxes"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."idle_ai_sandboxes"(integer, integer) to service_role;

-- Finishes a stop the caller claimed (service role): stopped, or back to
-- running with the error so the next run tries again. A stopped harness
-- sandbox also stops its session. False when a turn used the sandbox again
-- since the claim.
create or replace function "better_supabase"."finish_ai_sandbox_stop"(id uuid, stopped boolean, error text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
begin
  update "better_supabase"."ai_sandboxes" x set
    "status" = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    "stopped_at" = case when finish_ai_sandbox_stop.stopped then now() else null end,
    "error" = left(finish_ai_sandbox_stop.error, 4000),
    "updated_at" = now()
  where x."id" = finish_ai_sandbox_stop.id and x."status" = 'stopping'
  returning x.* into v_row;
  if not found then
    return false;
  end if;
  if finish_ai_sandbox_stop.stopped and v_row."harness_id" is not null then
    update "better_supabase"."ai_harness_sessions" z set "status" = 'stopped', "updated_at" = now()
    where z."chat_id" = v_row."chat_id" and z."harness_id" = v_row."harness_id"
      and z."status" in ('active', 'idle')
      and not exists (
        select 1 from "better_supabase"."ai_sandboxes" y
        where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped'
      );
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) to service_role;

create or replace function "better_supabase"."list_ai_sandboxes"(tenant uuid, chat_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'harness_id', x."harness_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from "better_supabase"."ai_sandboxes" x
  where x."organization_id" = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x."chat_id" = list_ai_sandboxes.chat_id)
$$;
revoke execute on function "better_supabase"."list_ai_sandboxes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_sandboxes"(uuid, uuid) to authenticated, service_role;

-- One run, when the caller may read its chat.
create or replace function "better_supabase"."get_ai_run"(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run "better_supabase"."ai_runs";
begin
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = get_ai_run.run;
  if not found or not "better_supabase"."ai_chat_can_read"(v_run."chat_id") then
    raise exception 'No run %', get_ai_run.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_run."id", 'chat_id', v_run."chat_id", 'owner_id', v_run."owner_id", 'assistant_message_id', v_run."assistant_message_id", 'stream_id', v_run."stream_id", 'engine', v_run."engine", 'external_run_id', v_run."external_run_id", 'model', v_run."model", 'status', v_run."status", 'usage', v_run."usage", 'cost_micro_usd', v_run."cost_micro_usd", 'error', v_run."error", 'started_at', v_run."started_at", 'ended_at', v_run."ended_at");
end;
$$;
revoke execute on function "better_supabase"."get_ai_run"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_run"(uuid) to authenticated, service_role;

-- Runs, newest first: a chat's when chat is set, else the caller's own
-- (every run for the service role). active keeps the unfinished ones.
create or replace function "better_supabase"."list_ai_runs"(chat uuid default null, active boolean default null, size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if list_ai_runs.chat is not null and not "better_supabase"."ai_chat_can_read"(list_ai_runs.chat) then
    raise exception 'No chat %', list_ai_runs.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'chat_id', y."chat_id", 'owner_id', y."owner_id", 'assistant_message_id', y."assistant_message_id", 'stream_id', y."stream_id", 'engine', y."engine", 'external_run_id', y."external_run_id", 'model', y."model", 'status', y."status", 'usage', y."usage", 'cost_micro_usd', y."cost_micro_usd", 'error', y."error", 'started_at', y."started_at", 'ended_at', y."ended_at") order by y."started_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."ai_runs" x
      where (
          case when list_ai_runs.chat is not null then x."chat_id" = list_ai_runs.chat
          else coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = (select auth.uid()) end
        )
        and (
          list_ai_runs.active is null
          or (x."status" in ('queued', 'running', 'cancel_requested')) = list_ai_runs.active
        )
      order by x."started_at" desc
      limit least(greatest(coalesce(list_ai_runs.size, 50), 1), 200)
    ) y
  );
end;
$$;
revoke execute on function "better_supabase"."list_ai_runs"(uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_runs"(uuid, boolean, integer) to authenticated, service_role;

-- Records the durable engine's run id on a run claimed before the engine
-- started (the service role only).
create or replace function "better_supabase"."attach_ai_run"(run uuid, external_run_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_runs" x set "external_run_id" = attach_ai_run.external_run_id
  where x."id" = attach_ai_run.run;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."attach_ai_run"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."attach_ai_run"(uuid, text) to service_role;

-- The caller's undecided approvals across chats, newest first, with the
-- chat's title: the approval inbox.
create or replace function "better_supabase"."list_pending_ai_tool_approvals"(size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.approval order by y.created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('approval_id', x."approval_id", 'chat_id', x."chat_id", 'run_id', x."run_id", 'message_id', x."message_id", 'tool', x."tool", 'tool_call_id', x."tool_call_id", 'input', x."input", 'decision', x."decision", 'reason', x."reason", 'signature', x."signature", 'decided_by', x."decided_by", 'decided_at', x."decided_at", 'created_at', x."created_at") || jsonb_build_object('chat_title', c."title") as approval, x."created_at" as created
    from "better_supabase"."ai_tool_approvals" x
    join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
    where x."owner_id" = (select auth.uid()) and x."decision" is null
    order by x."created_at" desc
    limit least(greatest(coalesce(list_pending_ai_tool_approvals.size, 50), 1), 200)
  ) y;
$$;
revoke execute on function "better_supabase"."list_pending_ai_tool_approvals"(integer) from public, anon;
grant execute on function "better_supabase"."list_pending_ai_tool_approvals"(integer) to authenticated, service_role;

-- Records one step of a run's progress (the service role only). step holds
-- key (the idempotency key), label, status and detail; a retry with the same
-- key updates the row and merges detail.
create or replace function "better_supabase"."record_ai_run_step"(run uuid, step jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run "better_supabase"."ai_runs";
  v_row "better_supabase"."ai_run_steps";
  v_status text := coalesce(record_ai_run_step.step ->> 'status', 'running');
  v_detail jsonb := coalesce(record_ai_run_step.step -> 'detail', '{}'::jsonb);
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = record_ai_run_step.run;
  if not found then
    raise exception 'No run %', record_ai_run_step.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  if nullif(record_ai_run_step.step ->> 'key', '') is null
    or v_status not in ('running', 'done', 'error', 'skipped')
    or jsonb_typeof(v_detail) <> 'object' then
    raise exception 'A step needs a key, a status of running, done, error or skipped and an object detail' using errcode = '22023', hint = 'AI_RUN_STEP_INVALID';
  end if;
  insert into "better_supabase"."ai_run_steps" ("run_id", "chat_id", "owner_id", "step_key", "label", "status", "detail", "ended_at")
  values (
    v_run."id", v_run."chat_id", v_run."owner_id", record_ai_run_step.step ->> 'key',
    coalesce(nullif(record_ai_run_step.step ->> 'label', ''), record_ai_run_step.step ->> 'key'),
    v_status, v_detail, case when v_status <> 'running' then now() end
  )
  on conflict ("run_id", "step_key") do update set
    "label" = coalesce(nullif(record_ai_run_step.step ->> 'label', ''), "better_supabase"."ai_run_steps"."label"),
    "status" = excluded."status",
    "detail" = "better_supabase"."ai_run_steps"."detail" || excluded."detail",
    "ended_at" = case when excluded."status" <> 'running' then coalesce("better_supabase"."ai_run_steps"."ended_at", now()) end
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_run."chat_id", null, 'run.step', jsonb_build_object('runId', v_run."id", 'key', v_row."step_key", 'status', v_row."status"), false);
  return jsonb_build_object('id', v_row."id", 'run_id', v_row."run_id", 'chat_id', v_row."chat_id", 'step_key', v_row."step_key", 'label', v_row."label", 'status', v_row."status", 'detail', v_row."detail", 'started_at', v_row."started_at", 'ended_at', v_row."ended_at");
end;
$$;
revoke execute on function "better_supabase"."record_ai_run_step"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."record_ai_run_step"(uuid, jsonb) to service_role;

-- A run's steps in the order they started.
create or replace function "better_supabase"."list_ai_run_steps"(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run "better_supabase"."ai_runs";
begin
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = list_ai_run_steps.run;
  if not found or not "better_supabase"."ai_chat_can_read"(v_run."chat_id") then
    raise exception 'No run %', list_ai_run_steps.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'run_id', x."run_id", 'chat_id', x."chat_id", 'step_key', x."step_key", 'label', x."label", 'status', x."status", 'detail', x."detail", 'started_at', x."started_at", 'ended_at', x."ended_at") order by x."started_at", x."id"), '[]'::jsonb)
    from "better_supabase"."ai_run_steps" x where x."run_id" = v_run."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_ai_run_steps"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_run_steps"(uuid) to authenticated, service_role;

-- A harness session's state, or null (the service role only). Experimental.
create or replace function "better_supabase"."load_ai_harness_session"(chat uuid, harness text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = load_ai_harness_session.chat and x."harness_id" = load_ai_harness_session.harness;
  if not found then
    return null;
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."load_ai_harness_session"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."load_ai_harness_session"(uuid, text) to service_role;

-- Saves a harness session (the service role only). fields may set
-- resume_state, continue_state, sandbox_id (with sandbox_provider) and
-- status; a key that is absent keeps its value. sandbox_id registers the
-- session's sandbox in ai_sandboxes, and null marks it stopped. A session
-- locked by another holder raises AI_HARNESS_LOCKED.
create or replace function "better_supabase"."save_ai_harness_session"(chat uuid, harness text, fields jsonb, holder text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
  v_status text := save_ai_harness_session.fields ->> 'status';
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(save_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if jsonb_typeof(save_ai_harness_session.fields) is distinct from 'object'
    or (v_status is not null and v_status not in ('active', 'idle', 'stopped', 'error')) then
    raise exception 'fields must be an object and status active, idle, stopped or error' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', save_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", save_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = save_ai_harness_session.harness
  for update;
  if v_row."locked_until" > now() and v_row."lock_holder" is distinct from save_ai_harness_session.holder then
    raise exception 'Harness session % is locked', save_ai_harness_session.harness using errcode = '55P03', hint = 'AI_HARNESS_LOCKED';
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "resume_state" = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x."resume_state" end,
    "continue_state" = case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x."continue_state" end,
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again.
    "status" = coalesce(v_status, case when x."status" = 'idle' then 'active' else x."status" end),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  if save_ai_harness_session.fields ? 'sandbox_id' then
    if nullif(save_ai_harness_session.fields ->> 'sandbox_id', '') is null then
      update "better_supabase"."ai_sandboxes" y set "status" = 'stopped', "stopped_at" = now(), "updated_at" = now()
      where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped';
    else
      insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id")
      values (v_chat."organization_id", v_chat."owner_id", v_chat."id", v_row."harness_id", coalesce(nullif(save_ai_harness_session.fields ->> 'sandbox_provider', ''), 'harness'), save_ai_harness_session.fields ->> 'sandbox_id')
      on conflict ("provider", "sandbox_id") do update set
        "chat_id" = excluded."chat_id",
        "harness_id" = excluded."harness_id",
        "status" = 'running',
        "error" = null,
        "stopped_at" = null,
        "last_used_at" = now(),
        "updated_at" = now()
      where cur."organization_id" = excluded."organization_id";
      if not found then
        raise exception 'sandbox % belongs to another tenant', save_ai_harness_session.fields ->> 'sandbox_id' using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
      end if;
    end if;
  elsif save_ai_harness_session.fields ->> 'status' is null then
    update "better_supabase"."ai_sandboxes" y set "last_used_at" = now(), "updated_at" = now()
    where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" = 'running';
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_ai_harness_session"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."save_ai_harness_session"(uuid, text, jsonb, text) to service_role;

-- Takes a harness session's lock for ttl_seconds (the service role only):
-- true when the caller holds it, false when another holder does.
create or replace function "better_supabase"."lock_ai_harness_session"(chat uuid, harness text, holder text, ttl_seconds integer default 300)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(lock_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if nullif(lock_ai_harness_session.holder, '') is null
    or coalesce(lock_ai_harness_session.ttl_seconds, 0) not between 1 and 86400 then
    raise exception 'A lock needs a holder and a ttl between 1 and 86400 seconds' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = lock_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', lock_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", lock_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = lock_ai_harness_session.harness
  for update;
  if v_row."locked_until" > now() and v_row."lock_holder" is distinct from lock_ai_harness_session.holder then
    return false;
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "lock_holder" = lock_ai_harness_session.holder,
    "locked_until" = now() + make_interval(secs => lock_ai_harness_session.ttl_seconds),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."lock_ai_harness_session"(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."lock_ai_harness_session"(uuid, text, text, integer) to service_role;

-- Releases a harness session's lock when holder holds it (the service role only).
create or replace function "better_supabase"."unlock_ai_harness_session"(chat uuid, harness text, holder text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_harness_sessions" x set "lock_holder" = null, "locked_until" = null, "updated_at" = now()
  where x."chat_id" = unlock_ai_harness_session.chat
    and x."harness_id" = unlock_ai_harness_session.harness
    and x."lock_holder" = unlock_ai_harness_session.holder;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."unlock_ai_harness_session"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."unlock_ai_harness_session"(uuid, text, text) to service_role;

-- A chat's readers join ai-chat:{chatId}; each user joins
-- ai-chats:{userId} for their sidebar. Payloads carry ids only.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_ai_chat_receive" on realtime.messages;
    create policy "bs_ai_chat_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'ai-chat:%'
        and substr((select realtime.topic()), 9) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and "better_supabase"."ai_chat_can_read"(substr((select realtime.topic()), 9)::uuid)
      );
    drop policy if exists "bs_ai_chats_receive" on realtime.messages;
    create policy "bs_ai_chats_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) = 'ai-chats:' || (select auth.uid())::text
      );
  end if;
end;
$$;

-- sql.modules.ai-chat.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."claim_ai_chat_stream"(uuid, text, text, text, text);

create or replace function "api"."ai_chat_can_read"(chat uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_chat_can_read"($1) $$;
revoke execute on function "api"."ai_chat_can_read"(uuid) from public, anon;
grant execute on function "api"."ai_chat_can_read"(uuid) to authenticated, service_role;

create or replace function "api"."create_ai_chat"(tenant uuid, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_ai_chat"($1, $2) $$;
revoke execute on function "api"."create_ai_chat"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_ai_chat"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_ai_chat"(chat uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_ai_chat"($1, $2) $$;
revoke execute on function "api"."update_ai_chat"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_ai_chat"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_ai_chat"(chat uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_chat"($1) $$;
revoke execute on function "api"."delete_ai_chat"(uuid) from public, anon;
grant execute on function "api"."delete_ai_chat"(uuid) to authenticated, service_role;

create or replace function "api"."get_ai_chat"(chat uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_chat"($1) $$;
revoke execute on function "api"."get_ai_chat"(uuid) from public, anon;
grant execute on function "api"."get_ai_chat"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_chats"(tenant uuid default null, search text default null, project uuid default null, pinned boolean default null, archived boolean default false, after text default null, size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_chats"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) from public, anon;
grant execute on function "api"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) to authenticated, service_role;

create or replace function "api"."save_ai_project"(id uuid, tenant uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_project"($1, $2, $3) $$;
revoke execute on function "api"."save_ai_project"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_ai_project"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_ai_project"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_project"($1) $$;
revoke execute on function "api"."delete_ai_project"(uuid) from public, anon;
grant execute on function "api"."delete_ai_project"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_projects"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_projects"($1) $$;
revoke execute on function "api"."list_ai_projects"(uuid) from public, anon;
grant execute on function "api"."list_ai_projects"(uuid) to authenticated, service_role;

create or replace function "api"."ai_message_path"(chat uuid, leaf text default null, include_native boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_message_path"($1, $2, $3) $$;
revoke execute on function "api"."ai_message_path"(uuid, text, boolean) from public, anon;
grant execute on function "api"."ai_message_path"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."ai_message_siblings"(chat uuid, message_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_message_siblings"($1, $2) $$;
revoke execute on function "api"."ai_message_siblings"(uuid, text) from public, anon;
grant execute on function "api"."ai_message_siblings"(uuid, text) to authenticated, service_role;

create or replace function "api"."switch_ai_branch"(chat uuid, message_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."switch_ai_branch"($1, $2) $$;
revoke execute on function "api"."switch_ai_branch"(uuid, text) from public, anon;
grant execute on function "api"."switch_ai_branch"(uuid, text) to authenticated, service_role;

create or replace function "api"."append_ai_user_message"(chat uuid, message jsonb, trigger text default 'submit-message', message_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."append_ai_user_message"($1, $2, $3, $4) $$;
revoke execute on function "api"."append_ai_user_message"(uuid, jsonb, text, text) from public, anon;
grant execute on function "api"."append_ai_user_message"(uuid, jsonb, text, text) to authenticated, service_role;

create or replace function "api"."save_ai_assistant_message"(chat uuid, message jsonb, parent_id text, status text default 'complete', model text default null, format text default 'canonical', native jsonb default null, run uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_assistant_message"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "api"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) to service_role;

create or replace function "api"."claim_ai_chat_stream"(chat uuid, stream text, model text default null, message_id text default null, engine text default 'ai-sdk', external_run_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_ai_chat_stream"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."claim_ai_chat_stream"(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."claim_ai_chat_stream"(uuid, text, text, text, text, text) to service_role;

create or replace function "api"."release_ai_chat_stream"(chat uuid, stream text, status text default 'completed', usage jsonb default null, generation_id text default null, error text default null, cost_micro_usd bigint default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_ai_chat_stream"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) from public, anon, authenticated;
grant execute on function "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) to service_role;

create or replace function "api"."request_ai_chat_stop"(chat uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_ai_chat_stop"($1) $$;
revoke execute on function "api"."request_ai_chat_stop"(uuid) from public, anon;
grant execute on function "api"."request_ai_chat_stop"(uuid) to authenticated, service_role;

create or replace function "api"."set_ai_run_cost"(generation_id text, cost_micro_usd bigint, usage jsonb default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_ai_run_cost"($1, $2, $3) $$;
revoke execute on function "api"."set_ai_run_cost"(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function "api"."set_ai_run_cost"(text, bigint, jsonb) to service_role;

create or replace function "api"."record_ai_tool_approval"(chat uuid, approval jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_ai_tool_approval"($1, $2) $$;
revoke execute on function "api"."record_ai_tool_approval"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."record_ai_tool_approval"(uuid, jsonb) to service_role;

create or replace function "api"."decide_ai_tool_approval"(approval_id text, approved boolean, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_ai_tool_approval"($1, $2, $3) $$;
revoke execute on function "api"."decide_ai_tool_approval"(text, boolean, text) from public, anon;
grant execute on function "api"."decide_ai_tool_approval"(text, boolean, text) to authenticated, service_role;

create or replace function "api"."get_ai_tool_approvals"(chat uuid, ids text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_tool_approvals"($1, $2) $$;
revoke execute on function "api"."get_ai_tool_approvals"(uuid, text[]) from public, anon;
grant execute on function "api"."get_ai_tool_approvals"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."set_ai_tool_policy"(tenant uuid, tool text, policy text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_ai_tool_policy"($1, $2, $3) $$;
revoke execute on function "api"."set_ai_tool_policy"(uuid, text, text) from public, anon;
grant execute on function "api"."set_ai_tool_policy"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."ai_tool_policies_for"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_tool_policies_for"($1) $$;
revoke execute on function "api"."ai_tool_policies_for"(uuid) from public, anon;
grant execute on function "api"."ai_tool_policies_for"(uuid) to authenticated, service_role;

create or replace function "api"."open_ai_pending_input"(chat uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_ai_pending_input"($1, $2) $$;
revoke execute on function "api"."open_ai_pending_input"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."open_ai_pending_input"(uuid, jsonb) to service_role;

create or replace function "api"."answer_ai_pending_input"(id uuid, answer jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."answer_ai_pending_input"($1, $2) $$;
revoke execute on function "api"."answer_ai_pending_input"(uuid, jsonb) from public, anon;
grant execute on function "api"."answer_ai_pending_input"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."rate_ai_message"(chat uuid, message_id text, rating integer, reason text default null, comment text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rate_ai_message"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."rate_ai_message"(uuid, text, integer, text, text) from public, anon;
grant execute on function "api"."rate_ai_message"(uuid, text, integer, text, text) to authenticated, service_role;

create or replace function "api"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."share_ai_chat"($1, $2) $$;
revoke execute on function "api"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "api"."share_ai_chat"(uuid, text) to authenticated, service_role;

create or replace function "api"."revoke_ai_chat_share"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_ai_chat_share"($1) $$;
revoke execute on function "api"."revoke_ai_chat_share"(uuid) from public, anon;
grant execute on function "api"."revoke_ai_chat_share"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_chat_shares"(chat uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_chat_shares"($1) $$;
revoke execute on function "api"."list_ai_chat_shares"(uuid) from public, anon;
grant execute on function "api"."list_ai_chat_shares"(uuid) to authenticated, service_role;

create or replace function "api"."get_shared_ai_chat"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_shared_ai_chat"($1) $$;
revoke execute on function "api"."get_shared_ai_chat"(text) from public;
grant execute on function "api"."get_shared_ai_chat"(text) to anon, authenticated, service_role;

create or replace function "api"."upsert_ai_models"(models jsonb, prune boolean default false)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_ai_models"($1, $2) $$;
revoke execute on function "api"."upsert_ai_models"(jsonb, boolean) from public, anon, authenticated;
grant execute on function "api"."upsert_ai_models"(jsonb, boolean) to service_role;

create or replace function "api"."allowed_ai_models"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."allowed_ai_models"($1) $$;
revoke execute on function "api"."allowed_ai_models"(uuid) from public, anon;
grant execute on function "api"."allowed_ai_models"(uuid) to authenticated, service_role;

create or replace function "api"."record_ai_moderation_event"(event jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_ai_moderation_event"($1) $$;
revoke execute on function "api"."record_ai_moderation_event"(jsonb) from public, anon, authenticated;
grant execute on function "api"."record_ai_moderation_event"(jsonb) to service_role;

create or replace function "api"."list_ai_moderation_events"(tenant uuid, size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_moderation_events"($1, $2) $$;
revoke execute on function "api"."list_ai_moderation_events"(uuid, integer) from public, anon;
grant execute on function "api"."list_ai_moderation_events"(uuid, integer) to authenticated, service_role;

create or replace function "api"."purge_ai_chats"(batch integer default 1000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_ai_chats"($1) $$;
revoke execute on function "api"."purge_ai_chats"(integer) from public, anon, authenticated;
grant execute on function "api"."purge_ai_chats"(integer) to service_role;

create or replace function "api"."register_ai_sandbox"(tenant uuid, provider text, sandbox_id text, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_ai_sandbox"($1, $2, $3, $4) $$;
revoke execute on function "api"."register_ai_sandbox"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."register_ai_sandbox"(uuid, text, text, jsonb) to service_role;

create or replace function "api"."touch_ai_sandbox"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."touch_ai_sandbox"($1) $$;
revoke execute on function "api"."touch_ai_sandbox"(uuid) from public, anon, authenticated;
grant execute on function "api"."touch_ai_sandbox"(uuid) to service_role;

create or replace function "api"."ai_sandbox_for"(chat_id uuid, provider text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_sandbox_for"($1, $2) $$;
revoke execute on function "api"."ai_sandbox_for"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."ai_sandbox_for"(uuid, text) to service_role;

create or replace function "api"."idle_ai_sandboxes"(batch integer default 50, lease_seconds integer default 300)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."idle_ai_sandboxes"($1, $2) $$;
revoke execute on function "api"."idle_ai_sandboxes"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."idle_ai_sandboxes"(integer, integer) to service_role;

create or replace function "api"."finish_ai_sandbox_stop"(id uuid, stopped boolean, error text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finish_ai_sandbox_stop"($1, $2, $3) $$;
revoke execute on function "api"."finish_ai_sandbox_stop"(uuid, boolean, text) from public, anon, authenticated;
grant execute on function "api"."finish_ai_sandbox_stop"(uuid, boolean, text) to service_role;

create or replace function "api"."list_ai_sandboxes"(tenant uuid, chat_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_sandboxes"($1, $2) $$;
revoke execute on function "api"."list_ai_sandboxes"(uuid, uuid) from public, anon;
grant execute on function "api"."list_ai_sandboxes"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."get_ai_run"(run uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_run"($1) $$;
revoke execute on function "api"."get_ai_run"(uuid) from public, anon;
grant execute on function "api"."get_ai_run"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_runs"(chat uuid default null, active boolean default null, size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_runs"($1, $2, $3) $$;
revoke execute on function "api"."list_ai_runs"(uuid, boolean, integer) from public, anon;
grant execute on function "api"."list_ai_runs"(uuid, boolean, integer) to authenticated, service_role;

create or replace function "api"."attach_ai_run"(run uuid, external_run_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."attach_ai_run"($1, $2) $$;
revoke execute on function "api"."attach_ai_run"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."attach_ai_run"(uuid, text) to service_role;

create or replace function "api"."list_pending_ai_tool_approvals"(size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pending_ai_tool_approvals"($1) $$;
revoke execute on function "api"."list_pending_ai_tool_approvals"(integer) from public, anon;
grant execute on function "api"."list_pending_ai_tool_approvals"(integer) to authenticated, service_role;

create or replace function "api"."record_ai_run_step"(run uuid, step jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_ai_run_step"($1, $2) $$;
revoke execute on function "api"."record_ai_run_step"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."record_ai_run_step"(uuid, jsonb) to service_role;

create or replace function "api"."list_ai_run_steps"(run uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_run_steps"($1) $$;
revoke execute on function "api"."list_ai_run_steps"(uuid) from public, anon;
grant execute on function "api"."list_ai_run_steps"(uuid) to authenticated, service_role;

create or replace function "api"."load_ai_harness_session"(chat uuid, harness text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."load_ai_harness_session"($1, $2) $$;
revoke execute on function "api"."load_ai_harness_session"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."load_ai_harness_session"(uuid, text) to service_role;

create or replace function "api"."save_ai_harness_session"(chat uuid, harness text, fields jsonb, holder text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_harness_session"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_ai_harness_session"(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."save_ai_harness_session"(uuid, text, jsonb, text) to service_role;

create or replace function "api"."lock_ai_harness_session"(chat uuid, harness text, holder text, ttl_seconds integer default 300)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."lock_ai_harness_session"($1, $2, $3, $4) $$;
revoke execute on function "api"."lock_ai_harness_session"(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function "api"."lock_ai_harness_session"(uuid, text, text, integer) to service_role;

create or replace function "api"."unlock_ai_harness_session"(chat uuid, harness text, holder text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unlock_ai_harness_session"($1, $2, $3) $$;
revoke execute on function "api"."unlock_ai_harness_session"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."unlock_ai_harness_session"(uuid, text, text) to service_role;

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
