-- ==== schema supabase/schemas/900_better_supabase_044_workflow_editor.sql
-- better-supabase module: workflow-editor
-- @bsb-block workflow-editor@3 managed
-- @bsb-hash sha256:0a8244d641581e8e20ec1b97d87ccddb7ea0af5a95e2d7390984bd993b63416b
-- Workflow definitions a tenant edits as an engine-neutral node graph, with draft, published and archived versions, triggers (webhook tokens stored hashed), credential references a CredentialProvider resolves, a synced step library, per-node run status pinged on the run's topic, and failed and slow alerts written as workflow_alert.triggered outbox events.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_opt_outs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_opt_outs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_opt_outs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_opt_outs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_opt_outs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_credentials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_credentials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_credentials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_credentials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_credentials";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Workflow definitions a tenant builds, by slug. Each has numbered versions:
-- at most one draft that the editor saves, at most one published version
-- that runs start from, and archived ones.
create table if not exists "better_supabase"."workflow_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "slug" text not null check ("slug" ~ '^[a-z0-9][a-z0-9-]{0,99}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint workflow_definitions_tenant_slug_key unique nulls not distinct ("tenant_id", "slug")
);
create index if not exists workflow_definitions_created_by_idx on "better_supabase"."workflow_definitions" ("created_by");
-- subject_types: the record types a run of the definition may belong to.
-- scope: a system definition has no tenant, every member with
-- workflow.read reads it, only the service role saves and publishes it, and
-- it runs in a tenant until the tenant opts out (workflow_opt_outs).
-- forked_from: the definition and version a fork copied.
-- restricted: running or editing it also needs a workflow_definition_grants
-- row (or workflow.admin).
alter table "better_supabase"."workflow_definitions" add column if not exists "subject_types" text[] not null default '{}';
alter table "better_supabase"."workflow_definitions" add column if not exists "scope" text not null default 'tenant'
  check ("scope" in ('tenant', 'system'));
alter table "better_supabase"."workflow_definitions" add column if not exists "forked_from" uuid references "better_supabase"."workflow_definitions" ("id") on delete set null;
alter table "better_supabase"."workflow_definitions" add column if not exists "forked_from_version" integer check ("forked_from_version" > 0);
alter table "better_supabase"."workflow_definitions" add column if not exists "restricted" boolean not null default false;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."workflow_definitions"'::regclass and c.conname = 'workflow_definitions_system_check'
  ), 'pg_constraint'), '') <> 'better-supabase check 02e502e1' then
    alter table "better_supabase"."workflow_definitions" drop constraint if exists "workflow_definitions_system_check";
    alter table "better_supabase"."workflow_definitions" add constraint "workflow_definitions_system_check" check ("scope" = 'tenant' or "tenant_id" is null);
    comment on constraint "workflow_definitions_system_check" on "better_supabase"."workflow_definitions" is 'better-supabase check 02e502e1';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."workflow_definitions"'::regclass and c.conname = 'workflow_definitions_subject_types_check'
  ), 'pg_constraint'), '') <> 'better-supabase check bdb3cf6a' then
    alter table "better_supabase"."workflow_definitions" drop constraint if exists "workflow_definitions_subject_types_check";
    alter table "better_supabase"."workflow_definitions" add constraint "workflow_definitions_subject_types_check" check (cardinality("subject_types") <= 50 and array_position("subject_types", null) is null);
    comment on constraint "workflow_definitions_subject_types_check" on "better_supabase"."workflow_definitions" is 'better-supabase check bdb3cf6a';
  end if;
end;
$$;
create index if not exists workflow_definitions_forked_from_idx on "better_supabase"."workflow_definitions" ("forked_from") where "forked_from" is not null;
alter table "better_supabase"."workflow_definitions" add column if not exists "app_note" text;
alter table "better_supabase"."workflow_definitions" enable row level security;
revoke all on "better_supabase"."workflow_definitions" from public, anon, authenticated;
grant select on "better_supabase"."workflow_definitions" to authenticated;
grant all on "better_supabase"."workflow_definitions" to service_role;
drop policy if exists workflow_definitions_read on "better_supabase"."workflow_definitions";
create policy workflow_definitions_read on "better_supabase"."workflow_definitions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')) or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('workflow.read'))));

-- The tenants that opted out of a definition, usually a system one: its
-- triggers and starts skip them (WORKFLOW_OPTED_OUT).
create table if not exists "better_supabase"."workflow_opt_outs" (
  "tenant_id" uuid not null,
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  primary key ("tenant_id", "definition_id")
);
create index if not exists workflow_opt_outs_definition_idx on "better_supabase"."workflow_opt_outs" ("definition_id");
create index if not exists workflow_opt_outs_created_by_idx on "better_supabase"."workflow_opt_outs" ("created_by");
alter table "better_supabase"."workflow_opt_outs" enable row level security;
revoke all on "better_supabase"."workflow_opt_outs" from public, anon, authenticated;
grant select on "better_supabase"."workflow_opt_outs" to authenticated;
grant all on "better_supabase"."workflow_opt_outs" to service_role;
drop policy if exists workflow_opt_outs_read on "better_supabase"."workflow_opt_outs";
create policy workflow_opt_outs_read on "better_supabase"."workflow_opt_outs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')));

-- Who may run or edit a restricted definition: a user, a team or an
-- organization role. An edit grant also runs it.
create table if not exists "better_supabase"."workflow_definition_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "principal_kind" text not null check ("principal_kind" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "action" text not null check ("action" in ('run', 'edit')),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint workflow_definition_grants_key unique ("definition_id", "principal_kind", "principal_id", "action")
);
create index if not exists workflow_definition_grants_principal_idx on "better_supabase"."workflow_definition_grants" ("principal_kind", "principal_id");
create index if not exists workflow_definition_grants_created_by_idx on "better_supabase"."workflow_definition_grants" ("created_by");
alter table "better_supabase"."workflow_definition_grants" enable row level security;
revoke all on "better_supabase"."workflow_definition_grants" from public, anon, authenticated;
grant select on "better_supabase"."workflow_definition_grants" to authenticated;
grant all on "better_supabase"."workflow_definition_grants" to service_role;
drop policy if exists workflow_definition_grants_read on "better_supabase"."workflow_definition_grants";
create policy workflow_definition_grants_read on "better_supabase"."workflow_definition_grants"
  for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

create table if not exists "better_supabase"."workflow_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "version" integer not null check ("version" > 0),
  "graph" jsonb not null default '{"nodes": [], "edges": []}'::jsonb,
  "compiled" jsonb,
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'archived')),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "published_at" timestamptz,
  constraint workflow_versions_definition_version_key unique ("definition_id", "version")
);
-- Who published a version and with which rights: its steps run as that
-- user, narrowed to permissions, or as the app's service principal when an
-- organization owns it (published by the service role). A deleted user
-- leaves published_by null with owner_kind 'user', so the steps fail.
alter table "better_supabase"."workflow_versions" add column if not exists "published_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."workflow_versions" add column if not exists "owner_kind" text check ("owner_kind" in ('user', 'organization'));
alter table "better_supabase"."workflow_versions" add column if not exists "permissions" text[] not null default '{}';
-- input_schema: the JSON Schema of the input a run of the version takes, as
-- the editor saved it; callers such as template attachments check against it.
alter table "better_supabase"."workflow_versions" add column if not exists "input_schema" jsonb
  check ("input_schema" is null or jsonb_typeof("input_schema") = 'object');
create index if not exists workflow_versions_published_by_idx on "better_supabase"."workflow_versions" ("published_by");
create unique index if not exists workflow_versions_one_draft_idx on "better_supabase"."workflow_versions" ("definition_id") where "status" = 'draft';
create unique index if not exists workflow_versions_one_published_idx on "better_supabase"."workflow_versions" ("definition_id") where "status" = 'published';
create index if not exists workflow_versions_created_by_idx on "better_supabase"."workflow_versions" ("created_by");
alter table "better_supabase"."workflow_versions" enable row level security;
revoke all on "better_supabase"."workflow_versions" from public, anon, authenticated;
grant select on "better_supabase"."workflow_versions" to authenticated;
grant all on "better_supabase"."workflow_versions" to service_role;
drop policy if exists workflow_versions_read on "better_supabase"."workflow_versions";
create policy workflow_versions_read on "better_supabase"."workflow_versions"
  for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

-- How runs of a definition start. A webhook trigger's token is stored as its
-- SHA-256 only; schedule, form and chat triggers keep their settings
-- in config for the app to bind.
create table if not exists "better_supabase"."workflow_triggers" (
  "id" uuid primary key default gen_random_uuid(),
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('manual', 'webhook', 'schedule', 'form', 'chat')),
  "config" jsonb not null default '{}'::jsonb,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists workflow_triggers_definition_idx on "better_supabase"."workflow_triggers" ("definition_id");
create index if not exists workflow_triggers_event_type_idx on "better_supabase"."workflow_triggers" (("config" ->> 'type'))
  where "kind" = 'event' and "enabled";
alter table "better_supabase"."workflow_triggers" enable row level security;
revoke all on "better_supabase"."workflow_triggers" from public, anon, authenticated;
grant select on "better_supabase"."workflow_triggers" to authenticated;
grant all on "better_supabase"."workflow_triggers" to service_role;
drop policy if exists workflow_triggers_read on "better_supabase"."workflow_triggers";
create policy workflow_triggers_read on "better_supabase"."workflow_triggers"
  for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

create table if not exists "better_supabase"."workflow_webhook_tokens" (
  "token_hash" bytea primary key,
  "trigger_id" uuid not null unique references "better_supabase"."workflow_triggers" ("id") on delete cascade,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."workflow_webhook_tokens" enable row level security;
revoke all on "better_supabase"."workflow_webhook_tokens" from public, anon, authenticated;
grant all on "better_supabase"."workflow_webhook_tokens" to service_role;

-- Credentials the steps of a tenant's workflows use. A row names the secret
-- with a credential_ref that a CredentialProvider resolves; it never holds
-- the secret, so graphs and run state never see a token.
create table if not exists "better_supabase"."workflow_credentials" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "kind" text not null check (length("kind") between 1 and 100),
  "name" text not null check (length("name") between 1 and 200),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref" -> 'provider') = 'string'),
  "scopes" text[] not null default '{}',
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint workflow_credentials_tenant_name_key unique nulls not distinct ("tenant_id", "name")
);
create index if not exists workflow_credentials_created_by_idx on "better_supabase"."workflow_credentials" ("created_by");
alter table "better_supabase"."workflow_credentials" enable row level security;
revoke all on "better_supabase"."workflow_credentials" from public, anon, authenticated;
grant select on "better_supabase"."workflow_credentials" to authenticated;
grant all on "better_supabase"."workflow_credentials" to service_role;
drop policy if exists workflow_credentials_read on "better_supabase"."workflow_credentials";
create policy workflow_credentials_read on "better_supabase"."workflow_credentials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')));

-- The steps the deployment provides, synced from code: the palette of the
-- builder and the names a published graph may use.
create table if not exists "better_supabase"."workflow_step_library" (
  "name" text primary key check ("name" ~ '^[A-Za-z][A-Za-z0-9_.-]{0,99}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "input_schema" jsonb not null default '{}'::jsonb,
  "output_schema" jsonb not null default '{}'::jsonb,
  "credential_kind" text,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."workflow_step_library" add column if not exists "operation" text
  check (length("operation") between 1 and 200);
alter table "better_supabase"."workflow_step_library" enable row level security;
revoke all on "better_supabase"."workflow_step_library" from public, anon, authenticated;
grant select on "better_supabase"."workflow_step_library" to authenticated;
grant all on "better_supabase"."workflow_step_library" to service_role;
drop policy if exists workflow_step_library_read on "better_supabase"."workflow_step_library";
create policy workflow_step_library_read on "better_supabase"."workflow_step_library"
  for select to authenticated
  using (true);

-- The status of each node of a run, by node id, written by the engine.
create table if not exists "better_supabase"."workflow_node_runs" (
  "run_id" uuid not null references "better_supabase"."workflow_runs" ("id") on delete cascade,
  "node_id" text not null check (length("node_id") between 1 and 100),
  "status" text not null check ("status" in ('running', 'waiting', 'completed', 'failed', 'skipped')),
  "attempts" integer not null default 0,
  "output" jsonb,
  "error" text,
  "started_at" timestamptz,
  "ended_at" timestamptz,
  primary key ("run_id", "node_id")
);
alter table "better_supabase"."workflow_node_runs" enable row level security;
revoke all on "better_supabase"."workflow_node_runs" from public, anon, authenticated;
grant select on "better_supabase"."workflow_node_runs" to authenticated;
grant all on "better_supabase"."workflow_node_runs" to service_role;
drop policy if exists workflow_node_runs_read on "better_supabase"."workflow_node_runs";
create policy workflow_node_runs_read on "better_supabase"."workflow_node_runs"
  for select to authenticated
  using ("run_id" in (select x."id" from "better_supabase"."workflow_runs" x));

-- Alerts on a definition's runs: failed fires when a run fails, slow when a
-- run is still unfinished after threshold (check_workflow_alerts). Each
-- fires once per run and writes a workflow_alert.triggered outbox event.
create table if not exists "better_supabase"."workflow_alerts" (
  "id" uuid primary key default gen_random_uuid(),
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "on_event" text not null check ("on_event" in ('failed', 'slow')),
  "threshold" interval,
  "channel" jsonb not null default '{}'::jsonb,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  constraint workflow_alerts_threshold_check check ("on_event" <> 'slow' or "threshold" > interval '0')
);
create index if not exists workflow_alerts_definition_idx on "better_supabase"."workflow_alerts" ("definition_id");
create index if not exists workflow_alerts_created_by_idx on "better_supabase"."workflow_alerts" ("created_by");
alter table "better_supabase"."workflow_alerts" enable row level security;
revoke all on "better_supabase"."workflow_alerts" from public, anon, authenticated;
grant select on "better_supabase"."workflow_alerts" to authenticated;
grant all on "better_supabase"."workflow_alerts" to service_role;
drop policy if exists workflow_alerts_read on "better_supabase"."workflow_alerts";
create policy workflow_alerts_read on "better_supabase"."workflow_alerts"
  for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

create table if not exists "better_supabase"."workflow_alert_fires" (
  "alert_id" uuid not null references "better_supabase"."workflow_alerts" ("id") on delete cascade,
  "run_id" uuid not null references "better_supabase"."workflow_runs" ("id") on delete cascade,
  "fired_at" timestamptz not null default now(),
  primary key ("alert_id", "run_id")
);
create index if not exists workflow_alert_fires_run_idx on "better_supabase"."workflow_alert_fires" ("run_id");
alter table "better_supabase"."workflow_alert_fires" enable row level security;
revoke all on "better_supabase"."workflow_alert_fires" from public, anon, authenticated;
grant all on "better_supabase"."workflow_alert_fires" to service_role;

-- Problems that keep a graph from being published, as messages; empty when
-- it may be. The step names must be in the step library.
create or replace function "better_supabase"."validate_workflow_graph"(graph jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_errors text[] := '{}';
  v_nodes jsonb := coalesce(graph -> 'nodes', 'null'::jsonb);
  v_edges jsonb := coalesce(graph -> 'edges', '[]'::jsonb);
  v_node jsonb;
  v_edge jsonb;
  v_ids text[] := '{}';
  v_triggers integer := 0;
begin
  if jsonb_typeof(v_nodes) <> 'array' or jsonb_typeof(v_edges) <> 'array' then
    return jsonb_build_array('A graph has a nodes array and an edges array');
  end if;
  for v_node in select value from jsonb_array_elements(v_nodes) loop
    if coalesce(jsonb_typeof(v_node -> 'id'), '') <> 'string' or (v_node ->> 'id') !~ '^[A-Za-z0-9_-]{1,100}$' then
      v_errors := array_append(v_errors, 'Every node has an id of 1 to 100 letters, digits, underscores or hyphens');
      continue;
    end if;
    if (v_node ->> 'id') = any (v_ids) then
      v_errors := array_append(v_errors, format('Node %s appears twice', v_node ->> 'id'));
    end if;
    v_ids := array_append(v_ids, v_node ->> 'id');
    if coalesce(v_node ->> 'kind', '') not in ('trigger', 'step', 'sleep', 'approval', 'condition') then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from "better_supabase"."workflow_step_library" s where s."name" = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers < 1 then
    v_errors := array_append(v_errors, 'A graph has at least one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$$;
revoke execute on function "better_supabase"."validate_workflow_graph"(jsonb) from public, anon;
grant execute on function "better_supabase"."validate_workflow_graph"(jsonb) to authenticated, service_role;

-- Creates a definition, or renames the one with the same tenant and slug:
-- the service role or workflow.edit in tenant (and an edit grant on a
-- restricted one). subject_types and restricted keep their value when null;
-- only workflow.admin changes restricted. A system definition (scope
-- 'system') has no tenant and only the service role saves it; the scope of
-- a saved definition never changes.
drop function if exists "better_supabase"."save_workflow_definition"(uuid, text, text, text);
-- fields: the extra columns (blocks["workflow-editor"].options.extraColumns) to set.
drop function if exists "better_supabase"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean);
create or replace function "better_supabase"."save_workflow_definition"(
  tenant uuid,
  slug text,
  name text,
  description text default null,
  subject_types text[] default null,
  scope text default null,
  restricted boolean default null, fields jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_definitions"%rowtype;
  v_scope text := coalesce(scope, 'tenant');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('tenant', 'system') then
    raise exception 'scope is tenant or system' using errcode = '22023', hint = 'WORKFLOW_SCOPE_INVALID';
  end if;
  if v_scope = 'system' and tenant is not null then
    raise exception 'A system workflow has no tenant' using errcode = '22023', hint = 'WORKFLOW_SCOPE_INVALID';
  end if;
  if v_scope = 'system' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role saves a system workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workflow_definitions" x
  where x."tenant_id" is not distinct from tenant and x."slug" = slug
  for update;
  if found then
    if scope is not null and scope <> v_row."scope" then
      raise exception 'A workflow''s scope never changes' using errcode = '22023', hint = 'WORKFLOW_SCOPE_FIXED';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."id"), false)
      or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_row."id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      )) then
      raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    if restricted is not null and restricted <> v_row."restricted" and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
      raise exception 'Only a workflow admin restricts a workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    update "better_supabase"."workflow_definitions" x set
      "name" = name,
      "description" = description,
      "subject_types" = coalesce(subject_types, x."subject_types"),
      "restricted" = coalesce(restricted, x."restricted"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(restricted, false) and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
      raise exception 'Only a workflow admin restricts a workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
    end if;
    insert into "better_supabase"."workflow_definitions" ("tenant_id", "slug", "name", "description", "subject_types", "scope", "restricted", "created_by")
    values (tenant, slug, name, description, coalesce(subject_types, '{}'), v_scope, coalesce(restricted, false), (select auth.uid()))
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "app_note" = case when save_workflow_definition.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."workflow_definitions", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(save_workflow_definition.fields) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  return (jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'subjectTypes', to_jsonb(v_row."subject_types"),
    'scope', v_row."scope",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'restricted', v_row."restricted",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
end;
$$;
revoke execute on function "better_supabase"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean, jsonb) from public, anon;
grant execute on function "better_supabase"."save_workflow_definition"(uuid, text, text, text, text[], text, boolean, jsonb) to authenticated, service_role;

-- The definitions the caller may read, by name, each with the number of its
-- published version and whether it has a draft. With tenant, the tenant's
-- definitions and the system ones, each with optedOut; with subject_type,
-- only the definitions that run on it. A fork has upstreamVersion (its
-- source's published version) and behind (whether that is newer than the
-- version it copied).
drop function if exists "better_supabase"."workflow_definitions_list"(uuid);
create or replace function "better_supabase"."workflow_definitions_list"(tenant uuid default null, subject_type text default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    (jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', u.version,
      'behind', coalesce(u.version > x."forked_from_version", false),
      'optedOut', case when workflow_definitions_list.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = workflow_definitions_list.tenant and oo."definition_id" = x."id") end
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_definitions" x
  left join lateral (
    select y."version" as version from "better_supabase"."workflow_versions" y
    where y."definition_id" = x."forked_from" and y."status" = 'published'
  ) u on true
  where (workflow_definitions_list.tenant is null
      or x."tenant_id" = workflow_definitions_list.tenant
      or x."scope" = 'system')
    and (workflow_definitions_list.subject_type is null
      or workflow_definitions_list.subject_type = any (x."subject_types"));
$$;
revoke execute on function "better_supabase"."workflow_definitions_list"(uuid, text) from public, anon;
grant execute on function "better_supabase"."workflow_definitions_list"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."workflow_definition_get"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select (jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) from "better_supabase"."workflow_definitions" x where x."id" = workflow_definition_get.definition;
$$;
revoke execute on function "better_supabase"."workflow_definition_get"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_definition_get"(uuid) to authenticated, service_role;

-- Deletes a definition with its versions, triggers and alerts: the service
-- role or workflow.admin in its tenant. Its runs stay.
create or replace function "better_supabase"."remove_workflow_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_definitions" x
  where x."id" = definition and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_definition"(uuid) to authenticated, service_role;

-- Saves graph as the definition's draft: updates the draft, or opens one
-- numbered after the last version. workflow.edit in its tenant, and an edit
-- grant on a restricted definition. A null input_schema keeps the draft's
-- current one.
drop function if exists "better_supabase"."save_workflow_draft"(uuid, jsonb);
create or replace function "better_supabase"."save_workflow_draft"(definition uuid, graph jsonb, input_schema jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  if input_schema is not null and jsonb_typeof(input_schema) <> 'object' then
    raise exception 'An input schema is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null,
    "input_schema" = coalesce(input_schema, x."input_schema")
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "input_schema", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
      coalesce(input_schema, (select y."input_schema" from "better_supabase"."workflow_versions" y
        where y."definition_id" = definition order by y."version" desc limit 1)),
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "updated_at" = now() where x."id" = definition;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_draft"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."save_workflow_draft"(uuid, jsonb, jsonb) to authenticated, service_role;

-- The permissions the step nodes of graph need, sorted and distinct: the
-- provider's workflow.node.<step> operation, else the operation the library
-- step names (the provider's key for it, else the name itself), else
-- workflow.run. Trigger, sleep, approval and condition nodes need none.
create or replace function "better_supabase"."workflow_graph_permissions"(graph jsonb)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(distinct x.p order by x.p), '{}'::text[])
  from (
    select coalesce(
      '{}'::jsonb ->> (n.value ->> 'step'),
      (select coalesce('{}'::jsonb ->> s."operation", s."operation")
        from "better_supabase"."workflow_step_library" s where s."name" = n.value ->> 'step'),
      'workflow.run'
    ) as p
    from jsonb_array_elements(
      case when jsonb_typeof(workflow_graph_permissions.graph -> 'nodes') = 'array'
        then workflow_graph_permissions.graph -> 'nodes' else '[]'::jsonb end
    ) n
    where n.value ->> 'kind' = 'step'
  ) x;
$$;
revoke execute on function "better_supabase"."workflow_graph_permissions"(jsonb) from public, anon;
grant execute on function "better_supabase"."workflow_graph_permissions"(jsonb) to authenticated, service_role;

-- Whom the steps of a published or archived version run as (service role;
-- call it for every step). A user-owned version needs its publisher to
-- still hold workflow.publish and every stored permission in the tenant;
-- otherwise it raises WORKFLOW_PUBLISHER_REVOKED and the step fails. An
-- organization-owned version returns publisher null, for the app's service
-- principal. A system definition has no tenant, so pass the
-- tenant its run belongs to; a tenant definition ignores tenant. The
-- trigger that started the run never changes the answer.
drop function if exists "better_supabase"."workflow_run_principal"(uuid);
create or replace function "better_supabase"."workflow_run_principal"(version uuid, tenant uuid default null)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_publisher uuid;
  v_missing text;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'This workflow version was never published' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  select case when x."scope" = 'system' then tenant else x."tenant_id" end into v_tenant
  from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if v_row."owner_kind" is null then
    raise exception 'This workflow version was published before publishers were recorded; publish it again'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
  end if;
  if v_row."owner_kind" = 'user' then
    if v_row."published_by" is null then
      raise exception 'The user who published this workflow no longer exists'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(array_append(v_row."permissions", 'workflow.publish')) p
    where not coalesce(better_supabase.can_user(v_row."published_by", 'tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'The user who published this workflow no longer holds %', v_missing
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
  end if;
  return jsonb_build_object(
    'publisher', coalesce(v_publisher, v_row."published_by"),
    'tenant', v_tenant,
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions")
  );
end;
$$;
revoke execute on function "better_supabase"."workflow_run_principal"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_run_principal"(uuid, uuid) to service_role;

-- Publishes a version: workflow.publish in its tenant (and an edit grant on
-- a restricted definition; a system one only the service role), a graph
-- validate_workflow_graph accepts, and every permission its steps need
-- (workflow_graph_permissions), which are stored with the publisher. The
-- service role publishes for the organization. The version published
-- before is archived. Only the service role may store the engine's
-- compiled form, also on a version that is already published.
create or replace function "better_supabase"."publish_workflow_version"(version uuid, compiled jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
  v_permissions text[];
  v_missing text[];
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."definition_id"), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_row."definition_id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := "better_supabase"."workflow_graph_permissions"(v_row."graph");
  if not v_service then
    select array_agg(p order by p) into v_missing
    from unnest(v_permissions) p
    where not coalesce(better_supabase.can('tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', array_to_string(v_missing, ', ')
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN',
          detail = jsonb_build_object('permissions', to_jsonb(v_missing))::text;
    end if;
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set
    "status" = 'published',
    "compiled" = compiled,
    "published_at" = now(),
    "published_by" = case when v_service then null else (select auth.uid()) end,
    "owner_kind" = case when v_service then 'organization' else 'user' end,
    "permissions" = v_permissions
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
end;
$$;
revoke execute on function "better_supabase"."publish_workflow_version"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."publish_workflow_version"(uuid, jsonb) to authenticated, service_role;

-- A definition's versions, newest first, without their graphs.
create or replace function "better_supabase"."workflow_versions_list"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'publishedBy', x."published_by",
    'owner', x."owner_kind",
    'permissions', to_jsonb(x."permissions")
  ) order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."workflow_versions" x where x."definition_id" = workflow_versions_list.definition;
$$;
revoke execute on function "better_supabase"."workflow_versions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_versions_list"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."workflow_version_get"(version uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'publishedBy', x."published_by",
    'owner', x."owner_kind",
    'permissions', to_jsonb(x."permissions"),
    'graph', x."graph",
    'compiled', x."compiled",
    'inputSchema', x."input_schema"
  ) from "better_supabase"."workflow_versions" x where x."id" = workflow_version_get.version;
$$;
revoke execute on function "better_supabase"."workflow_version_get"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_version_get"(uuid) to authenticated, service_role;

-- What a run of definition starts from: the tenant it runs in and the
-- published version. workflow.run in that tenant (and a run grant on a
-- restricted definition), or the service role. A system definition runs in
-- tenant, which it needs; a tenant that opted out of the definition gets
-- WORKFLOW_OPTED_OUT.
drop function if exists "better_supabase"."workflow_start_target"(uuid);
create or replace function "better_supabase"."workflow_start_target"(definition uuid, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  v_tenant := case when v_def."scope" = 'system' then tenant else v_def."tenant_id" end;
  if v_def."scope" = 'system' and v_tenant is null then
    raise exception 'Pass the tenant a system workflow runs in' using errcode = '22023', hint = 'WORKFLOW_TENANT_REQUIRED';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.run'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('run', 'edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not run this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_tenant is not null and exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = v_tenant and oo."definition_id" = definition) then
    raise exception 'This organization opted out of this workflow' using errcode = 'P0001', hint = 'WORKFLOW_OPTED_OUT';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."definition_id" = definition and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', (jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'subjectTypes', to_jsonb(v_def."subject_types"),
    'scope', v_def."scope",
    'forkedFrom', v_def."forked_from",
    'forkedFromVersion', v_def."forked_from_version",
    'restricted', v_def."restricted",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', v_def."app_note"))), 'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  ), 'tenant', v_tenant);
end;
$$;
revoke execute on function "better_supabase"."workflow_start_target"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."workflow_start_target"(uuid, uuid) to authenticated, service_role;

-- workflow_start_target for a run that belongs to a record: the definition
-- must list subject_type in subject_types. Security invoker, so the
-- record check runs under the caller's RLS; returns the target with the
-- subject.
create or replace function "better_supabase"."workflow_subject_start_target"(
  definition uuid,
  subject_type text,
  subject_id text,
  tenant uuid default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_types text[];
begin
  if subject_type is null or subject_id is null or length(subject_type) not between 1 and 100 or length(subject_id) not between 1 and 200 then
    raise exception 'A subject has a type of 1 to 100 and an id of 1 to 200 characters' using errcode = '22023', hint = 'WORKFLOW_SUBJECT_INVALID';
  end if;
  select x."subject_types" into v_types from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (subject_type = any (v_types)) then
    raise exception 'This workflow doesn''t run on that subject type' using errcode = '22023', hint = 'WORKFLOW_SUBJECT_TYPE';
  end if;
  return "better_supabase"."workflow_start_target"(definition, tenant)
    || jsonb_build_object('subject', jsonb_build_object('type', subject_type, 'id', subject_id));
end;
$$;
revoke execute on function "better_supabase"."workflow_subject_start_target"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."workflow_subject_start_target"(uuid, text, text, uuid) to authenticated, service_role;

-- What a test run of definition starts from: version (default its draft,
-- else its published version), the trigger node it starts at (default the
-- graph's only trigger) and the stubs its steps return. workflow.edit in its
-- tenant (and an edit grant on a restricted definition). The run records
-- mode test: its steps don't run, and it fires no alerts and writes no
-- outbox events.
create or replace function "better_supabase"."start_test_run"(
  definition uuid,
  version uuid default null,
  trigger_node text default null,
  input jsonb default null,
  stubs jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_errors jsonb;
  v_triggers text[];
  v_node text := trigger_node;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_def."tenant_id" and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not test this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if stubs is not null and jsonb_typeof(stubs) <> 'object' then
    raise exception 'stubs is an object keyed by node id' using errcode = '22023', hint = 'WORKFLOW_STUBS_INVALID';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x
  where x."definition_id" = definition
    and (case when version is null then x."status" in ('draft', 'published') else x."id" = version end)
  order by x."status" = 'draft' desc
  limit 1;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  select array_agg(n.value ->> 'id') into v_triggers
  from jsonb_array_elements(v_row."graph" -> 'nodes') n
  where n.value ->> 'kind' = 'trigger';
  if v_node is null and cardinality(v_triggers) = 1 then
    v_node := v_triggers[1];
  end if;
  if v_node is null or not (v_node = any (v_triggers)) then
    raise exception 'Pass trigger_node, the id of one of the graph''s trigger nodes' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_NODE';
  end if;
  return jsonb_build_object(
    'definition', (jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'subjectTypes', to_jsonb(v_def."subject_types"),
    'scope', v_def."scope",
    'forkedFrom', v_def."forked_from",
    'forkedFromVersion', v_def."forked_from_version",
    'restricted', v_def."restricted",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', v_def."app_note"))),
    'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  ),
    'tenant', v_def."tenant_id",
    'triggerNode', v_node,
    'input', coalesce(input, '{}'::jsonb),
    'stubs', coalesce(stubs, '{}'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."start_test_run"(uuid, uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."start_test_run"(uuid, uuid, text, jsonb, jsonb) to authenticated, service_role;

-- Copies the published graph of source (a system definition, or one in
-- tenant) into a new definition in tenant with slug, as its draft, and
-- records the version it copied. workflow.edit in tenant (and an edit grant
-- on a restricted source).
create or replace function "better_supabase"."fork_workflow_definition"(source uuid, tenant uuid, slug text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src "better_supabase"."workflow_definitions"%rowtype;
  v_version "better_supabase"."workflow_versions"%rowtype;
  v_row "better_supabase"."workflow_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."workflow_definitions" x where x."id" = source;
  if not found or not (v_src."scope" = 'system' or v_src."tenant_id" is not distinct from tenant) then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_src."scope" = 'tenant' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = source), false)
      or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = source
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      )) then
    raise exception 'You may not fork this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."workflow_versions" x where x."definition_id" = source and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."workflow_definitions" ("tenant_id", "slug", "name", "description", "subject_types", "forked_from", "forked_from_version", "created_by")
  values (tenant, slug, v_src."name", v_src."description", v_src."subject_types", v_src."id", v_version."version", (select auth.uid()))
  returning * into v_row;
  insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "input_schema", "created_by")
  values (v_row."id", 1, v_version."graph", v_version."input_schema", (select auth.uid()));
  return (jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'subjectTypes', to_jsonb(v_row."subject_types"),
    'scope', v_row."scope",
    'forkedFrom', v_row."forked_from",
    'forkedFromVersion', v_row."forked_from_version",
    'restricted', v_row."restricted",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  ) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note"))) || jsonb_build_object('draft', true, 'upstreamVersion', v_version."version", 'behind', false);
end;
$$;
revoke execute on function "better_supabase"."fork_workflow_definition"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."fork_workflow_definition"(uuid, uuid, text) to authenticated, service_role;

-- Opts tenant out of definition (a system definition, or one in tenant), or
-- back in with opted_out false: workflow.admin in tenant. Returns whether
-- the tenant is opted out.
create or replace function "better_supabase"."set_workflow_opt_out"(tenant uuid, definition uuid, opted_out boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if tenant is null then
    raise exception 'Pass the tenant that opts out' using errcode = '22023', hint = 'WORKFLOW_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."workflow_definitions" x
    where x."id" = definition and (x."scope" = 'system' or x."tenant_id" = tenant)
  ) then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if coalesce(opted_out, true) then
    insert into "better_supabase"."workflow_opt_outs" ("tenant_id", "definition_id", "created_by")
    values (tenant, definition, (select auth.uid()))
    on conflict do nothing;
  else
    delete from "better_supabase"."workflow_opt_outs" x where x."tenant_id" = tenant and x."definition_id" = definition;
  end if;
  return coalesce(opted_out, true);
end;
$$;
revoke execute on function "better_supabase"."set_workflow_opt_out"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_workflow_opt_out"(uuid, uuid, boolean) to authenticated, service_role;

-- Grants (or with granted false, revokes) action (run or edit) on a
-- definition to a user, a team or an organization role: workflow.admin in
-- its tenant. Grants only matter while the definition is restricted.
create or replace function "better_supabase"."set_workflow_definition_grant"(
  definition uuid,
  principal_kind text,
  principal_id text,
  action text,
  granted boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage access to this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if principal_kind is null or principal_kind not in ('user', 'team', 'role') then
    raise exception 'principal_kind is user, team or role' using errcode = '22023', hint = 'WORKFLOW_GRANT_INVALID';
  end if;
  if action is null or action not in ('run', 'edit') then
    raise exception 'action is run or edit' using errcode = '22023', hint = 'WORKFLOW_GRANT_INVALID';
  end if;
  if coalesce(granted, true) then
    insert into "better_supabase"."workflow_definition_grants" ("definition_id", "principal_kind", "principal_id", "action", "created_by")
    values (definition, principal_kind, principal_id, action, (select auth.uid()))
    on conflict on constraint workflow_definition_grants_key do nothing;
  else
    delete from "better_supabase"."workflow_definition_grants" x
    where x."definition_id" = definition and x."principal_kind" = principal_kind
      and x."principal_id" = principal_id and x."action" = action;
  end if;
  return coalesce(granted, true);
end;
$$;
revoke execute on function "better_supabase"."set_workflow_definition_grant"(uuid, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_workflow_definition_grant"(uuid, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."workflow_definition_grants_list"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'action', x."action",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_definition_grants" x where x."definition_id" = workflow_definition_grants_list.definition;
$$;
revoke execute on function "better_supabase"."workflow_definition_grants_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_definition_grants_list"(uuid) to authenticated, service_role;

-- Creates or updates a trigger: workflow.edit in the definition's tenant.
create or replace function "better_supabase"."save_workflow_trigger"(
  definition uuid,
  kind text,
  config jsonb default '{}'::jsonb,
  enabled boolean default true,
  trigger uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_triggers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if trigger is null then
    insert into "better_supabase"."workflow_triggers" ("definition_id", "kind", "config", "enabled")
    values (definition, kind, coalesce(config, '{}'::jsonb), coalesce(enabled, true))
    returning * into v_row;
  else
    update "better_supabase"."workflow_triggers" x set
      "kind" = kind,
      "config" = coalesce(config, '{}'::jsonb),
      "enabled" = coalesce(enabled, true),
      "updated_at" = now()
    where x."id" = trigger and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
    if kind <> 'webhook' then
      delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'kind', v_row."kind",
    'config', v_row."config",
    'enabled', v_row."enabled",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."workflow_triggers_list"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_triggers" x where x."definition_id" = workflow_triggers_list.definition;
$$;
revoke execute on function "better_supabase"."workflow_triggers_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_triggers_list"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_workflow_trigger"(trigger uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_triggers" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = trigger and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.edit'), false)))
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = y."id"), false)
      or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = y."id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = y."tenant_id" and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_trigger"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_trigger"(uuid) to authenticated, service_role;

-- Issues a new token for a webhook trigger and returns it; only its SHA-256
-- is kept, so the old token stops working. workflow.edit in its tenant.
create or replace function "better_supabase"."rotate_workflow_webhook_token"(trigger uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_definition uuid;
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."tenant_id", y."id", x."kind" into v_tenant, v_definition, v_kind
  from "better_supabase"."workflow_triggers" x join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."id" = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_definition), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_definition
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id" and mr."disabled_at" is null)))
      ))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_kind <> 'webhook' then
    raise exception 'Only webhook triggers have tokens' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_KIND';
  end if;
  delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
  insert into "better_supabase"."workflow_webhook_tokens" ("token_hash", "trigger_id")
  values (extensions.digest(v_token, 'sha256'), trigger);
  return v_token;
end;
$$;
revoke execute on function "better_supabase"."rotate_workflow_webhook_token"(uuid) from public, anon;
grant execute on function "better_supabase"."rotate_workflow_webhook_token"(uuid) to authenticated, service_role;

-- The enabled webhook trigger a token belongs to, with its definition and
-- tenant (service role; the webhook route calls it).
create or replace function "better_supabase"."workflow_webhook_target"(token text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('trigger', jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ), 'tenant', y."tenant_id")
  from "better_supabase"."workflow_webhook_tokens" k
  join "better_supabase"."workflow_triggers" x on x."id" = k."trigger_id"
  join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where k."token_hash" = extensions.digest(workflow_webhook_target.token, 'sha256')
    and x."enabled";
$$;
revoke execute on function "better_supabase"."workflow_webhook_target"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_webhook_target"(text) to service_role;

-- Creates or replaces a credential reference: workflow.admin in tenant.
create or replace function "better_supabase"."save_workflow_credential"(
  tenant uuid,
  kind text,
  name text,
  ref jsonb,
  scopes text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflow credentials here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_workflow_credential.ref is not null and jsonb_typeof(save_workflow_credential.ref) <> 'null'
    and (jsonb_typeof(save_workflow_credential.ref -> 'tenant') is distinct from 'string' or (save_workflow_credential.ref ->> 'tenant') is distinct from (save_workflow_credential.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_workflow_credential.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."workflow_credentials" as x ("tenant_id", "kind", "name", "credential_ref", "scopes", "created_by")
  values (tenant, kind, name, ref, coalesce(scopes, '{}'), (select auth.uid()))
  on conflict on constraint workflow_credentials_tenant_name_key do update set
    "kind" = excluded."kind",
    "credential_ref" = excluded."credential_ref",
    "scopes" = excluded."scopes"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_credential"(uuid, text, text, jsonb, text[]) from public, anon;
grant execute on function "better_supabase"."save_workflow_credential"(uuid, text, text, jsonb, text[]) to authenticated, service_role;

create or replace function "better_supabase"."workflow_credentials_list"(tenant uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'kind', x."kind",
    'name', x."name",
    'ref', x."credential_ref",
    'scopes', to_jsonb(x."scopes"),
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_credentials" x
  where workflow_credentials_list.tenant is null or x."tenant_id" = workflow_credentials_list.tenant;
$$;
revoke execute on function "better_supabase"."workflow_credentials_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_credentials_list"(uuid) to authenticated, service_role;

-- One credential row with its reference (service role; steps resolve it).
create or replace function "better_supabase"."workflow_credential_get"(credential uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'kind', x."kind",
    'name', x."name",
    'ref', x."credential_ref",
    'scopes', to_jsonb(x."scopes"),
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) from "better_supabase"."workflow_credentials" x where x."id" = workflow_credential_get.credential;
$$;
revoke execute on function "better_supabase"."workflow_credential_get"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_credential_get"(uuid) to service_role;

-- Deletes a credential row and returns it, so the caller can revoke the
-- secret it names: workflow.admin in its tenant.
create or replace function "better_supabase"."remove_workflow_credential"(credential uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_credentials" x
  where x."id" = credential and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)))
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_credential"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_credential"(uuid) to authenticated, service_role;

-- Replaces the step library with steps, keyed by name ({ name: { title,
-- description, inputSchema, outputSchema, credentialKind, operation } });
-- returns how
-- many there are.
create or replace function "better_supabase"."sync_workflow_steps"(steps jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "better_supabase"."workflow_step_library" ("name", "title", "description", "input_schema", "output_schema", "credential_kind", "operation")
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce(e.value -> 'inputSchema', '{}'::jsonb), coalesce(e.value -> 'outputSchema', '{}'::jsonb), e.value ->> 'credentialKind',
    nullif(e.value ->> 'operation', '')
  from jsonb_each(coalesce(steps, '{}'::jsonb)) e
  on conflict ("name") do update set
    "title" = excluded."title",
    "description" = excluded."description",
    "input_schema" = excluded."input_schema",
    "output_schema" = excluded."output_schema",
    "credential_kind" = excluded."credential_kind",
    "operation" = excluded."operation",
    "updated_at" = now();
  delete from "better_supabase"."workflow_step_library" x
  where not exists (
    select 1 from jsonb_each(coalesce(steps, '{}'::jsonb)) e where e.key = x."name"
  );
  select count(*) into v_count from "better_supabase"."workflow_step_library";
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."sync_workflow_steps"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_workflow_steps"(jsonb) to service_role;

create or replace function "better_supabase"."workflow_steps_list"()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', x."name",
    'title', x."title",
    'description', x."description",
    'inputSchema', x."input_schema",
    'outputSchema', x."output_schema",
    'credentialKind', x."credential_kind",
    'operation', x."operation",
    'updatedAt', x."updated_at"
  ) order by x."name"), '[]'::jsonb) from "better_supabase"."workflow_step_library" x;
$$;
revoke execute on function "better_supabase"."workflow_steps_list"() from public, anon;
grant execute on function "better_supabase"."workflow_steps_list"() to authenticated, service_role;

-- Records a node's status for a run (by its id or its engine's id) and
-- pings the run's topic. attempt raises attempts; started_at keeps the
-- first start and ended_at is set by completed, failed and skipped.
create or replace function "better_supabase"."record_workflow_node_run"(
  run text,
  node text,
  status text,
  attempt integer default null,
  output jsonb default null,
  error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run uuid;
  v_ended boolean := status in ('completed', 'failed', 'skipped');
begin
  select x."id" into v_run from "better_supabase"."workflow_runs" x
  where x."id"::text = run or x."external_id" = run
  order by x."id"::text = run desc
  limit 1;
  if not found then
    return false;
  end if;
  insert into "better_supabase"."workflow_node_runs" as x ("run_id", "node_id", "status", "attempts", "output", "error", "started_at", "ended_at")
  values (v_run, node, status, coalesce(attempt, 0), output, left(error, 4000), now(), case when v_ended then now() end)
  on conflict ("run_id", "node_id") do update set
    "status" = excluded."status",
    "attempts" = greatest(x."attempts", excluded."attempts"),
    "output" = coalesce(excluded."output", x."output"),
    "error" = excluded."error",
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "ended_at" = excluded."ended_at";
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_run, 'node', node, 'status', status), 'node', 'workflow-run:' || v_run::text, true);
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text) to service_role;

-- The node statuses of a run the caller may read.
create or replace function "better_supabase"."workflow_node_runs_list"(run text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'run', x."run_id",
    'node', x."node_id",
    'status', x."status",
    'attempts', x."attempts",
    'output', x."output",
    'error', x."error",
    'startedAt', x."started_at",
    'endedAt', x."ended_at"
  ) order by x."started_at" nulls last, x."node_id"), '[]'::jsonb)
  from "better_supabase"."workflow_node_runs" x
  join "better_supabase"."workflow_runs" y on y."id" = x."run_id"
  where y."id"::text = workflow_node_runs_list.run or y."external_id" = workflow_node_runs_list.run;
$$;
revoke execute on function "better_supabase"."workflow_node_runs_list"(text) from public, anon;
grant execute on function "better_supabase"."workflow_node_runs_list"(text) to authenticated, service_role;

-- Creates or updates an alert: workflow.admin in the definition's tenant.
-- threshold (slow alerts) is how long a run may stay unfinished.
create or replace function "better_supabase"."save_workflow_alert"(
  definition uuid,
  on_event text,
  channel jsonb default '{}'::jsonb,
  threshold interval default null,
  alert uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_alerts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage alerts for this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if alert is null then
    insert into "better_supabase"."workflow_alerts" ("definition_id", "on_event", "threshold", "channel", "created_by")
    values (definition, on_event, threshold, coalesce(channel, '{}'::jsonb), (select auth.uid()))
    returning * into v_row;
  else
    update "better_supabase"."workflow_alerts" x set "on_event" = on_event, "threshold" = threshold, "channel" = coalesce(channel, '{}'::jsonb)
    where x."id" = alert and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such alert' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'onEvent', v_row."on_event",
    'threshold', extract(epoch from v_row."threshold"),
    'channel', v_row."channel",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) from public, anon;
grant execute on function "better_supabase"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) to authenticated, service_role;

create or replace function "better_supabase"."workflow_alerts_list"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'onEvent', x."on_event",
    'threshold', extract(epoch from x."threshold"),
    'channel', x."channel",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_alerts" x where x."definition_id" = workflow_alerts_list.definition;
$$;
revoke execute on function "better_supabase"."workflow_alerts_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_alerts_list"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_workflow_alert"(alert uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_alerts" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = alert and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_alert"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_alert"(uuid) to authenticated, service_role;

-- Fires the failed alerts of a run's definition (the bsb.definition
-- attribute) when a live run fails; test runs fire none.
create or replace function "better_supabase"."workflow_runs_alert"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run "better_supabase"."workflow_runs"%rowtype := new;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_fired integer := 0;
begin
  if new."mode" = 'test' or new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bsb.definition'
  loop
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_runs_alert"() from public, anon, authenticated;
drop trigger if exists "bsb_workflow_runs_alert" on "better_supabase"."workflow_runs";
create trigger "bsb_workflow_runs_alert" after insert or update of "status" on "better_supabase"."workflow_runs"
  for each row execute function "better_supabase"."workflow_runs_alert"();

-- Fires the slow alerts whose runs are still unfinished after their
-- threshold, at most batch per call; returns how many fired. Call it from
-- a cron route or a job.
create or replace function "better_supabase"."check_workflow_alerts"(batch integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pair record;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_run "better_supabase"."workflow_runs"%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x."id" as alert, y."id" as run from "better_supabase"."workflow_alerts" x
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bsb.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
      and y."mode" = 'live'
      and y."status" in ('queued', 'running', 'waiting')
      and y."created_at" < now() - x."threshold"
      and not exists (select 1 from "better_supabase"."workflow_alert_fires" z where z."alert_id" = x."id" and z."run_id" = y."id")
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from "better_supabase"."workflow_alerts" x where x."id" = v_pair.alert;
    select * into v_run from "better_supabase"."workflow_runs" x where x."id" = v_pair.run;
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return v_fired;
end;
$$;
revoke execute on function "better_supabase"."check_workflow_alerts"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."check_workflow_alerts"(integer) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."workflow_definitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')) or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('workflow.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."workflow_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."workflow_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."workflow_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_opt_outs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_opt_outs";
create policy bsb_tenant_scope_select on "better_supabase"."workflow_opt_outs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_opt_outs";
create policy bsb_tenant_scope_insert on "better_supabase"."workflow_opt_outs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_opt_outs";
create policy bsb_tenant_scope_update on "better_supabase"."workflow_opt_outs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_opt_outs";
create policy bsb_tenant_scope_delete on "better_supabase"."workflow_opt_outs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."workflow_credentials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."workflow_credentials";
create policy bsb_tenant_scope_select on "better_supabase"."workflow_credentials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."workflow_credentials";
create policy bsb_tenant_scope_insert on "better_supabase"."workflow_credentials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."workflow_credentials";
create policy bsb_tenant_scope_update on "better_supabase"."workflow_credentials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."workflow_credentials";
create policy bsb_tenant_scope_delete on "better_supabase"."workflow_credentials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_044_workflow_editor.sql
-- better-supabase module: workflow-editor
-- @bsb-block-data workflow-editor
-- @bsb-hash sha256:d5db3c041919731ba718ee42239ffde0ac7f82c38c8583aaa448c1dc0119e8a2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('workflow-editor', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
