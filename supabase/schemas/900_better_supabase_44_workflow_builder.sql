-- better-supabase module: workflow-builder (0.5.1)
-- @bs-module workflow-builder@1 managed
-- Workflow definitions a tenant edits as an engine-neutral node graph, with draft, published and archived versions, triggers (webhook tokens stored hashed), credential references a CredentialProvider resolves, a synced step library, per-node run status pinged on the run's topic, and failed and slow alerts written as workflow_alert.triggered outbox events.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
alter table "better_supabase"."workflow_definitions" enable row level security;
revoke all on "better_supabase"."workflow_definitions" from anon, authenticated;
grant select on "better_supabase"."workflow_definitions" to authenticated;
grant all on "better_supabase"."workflow_definitions" to service_role;
drop policy if exists workflow_definitions_read on "better_supabase"."workflow_definitions";
create policy workflow_definitions_read on "better_supabase"."workflow_definitions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('workflow.read')));

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
create unique index if not exists workflow_versions_one_draft_idx on "better_supabase"."workflow_versions" ("definition_id") where "status" = 'draft';
create unique index if not exists workflow_versions_one_published_idx on "better_supabase"."workflow_versions" ("definition_id") where "status" = 'published';
create index if not exists workflow_versions_created_by_idx on "better_supabase"."workflow_versions" ("created_by");
alter table "better_supabase"."workflow_versions" enable row level security;
revoke all on "better_supabase"."workflow_versions" from anon, authenticated;
grant select on "better_supabase"."workflow_versions" to authenticated;
grant all on "better_supabase"."workflow_versions" to service_role;
drop policy if exists workflow_versions_read on "better_supabase"."workflow_versions";
create policy workflow_versions_read on "better_supabase"."workflow_versions" for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

-- How runs of a definition start. A webhook trigger's token is stored as its
-- SHA-256 only; schedule, event, form and chat triggers keep their settings
-- in config for the app to bind.
create table if not exists "better_supabase"."workflow_triggers" (
  "id" uuid primary key default gen_random_uuid(),
  "definition_id" uuid not null references "better_supabase"."workflow_definitions" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('manual', 'webhook', 'schedule', 'event', 'form', 'chat')),
  "config" jsonb not null default '{}'::jsonb,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists workflow_triggers_definition_idx on "better_supabase"."workflow_triggers" ("definition_id");
alter table "better_supabase"."workflow_triggers" enable row level security;
revoke all on "better_supabase"."workflow_triggers" from anon, authenticated;
grant select on "better_supabase"."workflow_triggers" to authenticated;
grant all on "better_supabase"."workflow_triggers" to service_role;
drop policy if exists workflow_triggers_read on "better_supabase"."workflow_triggers";
create policy workflow_triggers_read on "better_supabase"."workflow_triggers" for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

create table if not exists "better_supabase"."workflow_webhook_tokens" (
  "token_hash" bytea primary key,
  "trigger_id" uuid not null unique references "better_supabase"."workflow_triggers" ("id") on delete cascade,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."workflow_webhook_tokens" enable row level security;
revoke all on "better_supabase"."workflow_webhook_tokens" from anon, authenticated;
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
revoke all on "better_supabase"."workflow_credentials" from anon, authenticated;
grant select on "better_supabase"."workflow_credentials" to authenticated;
grant all on "better_supabase"."workflow_credentials" to service_role;
drop policy if exists workflow_credentials_read on "better_supabase"."workflow_credentials";
create policy workflow_credentials_read on "better_supabase"."workflow_credentials" for select to authenticated
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
alter table "better_supabase"."workflow_step_library" enable row level security;
revoke all on "better_supabase"."workflow_step_library" from anon, authenticated;
grant select on "better_supabase"."workflow_step_library" to authenticated;
grant all on "better_supabase"."workflow_step_library" to service_role;
drop policy if exists workflow_step_library_read on "better_supabase"."workflow_step_library";
create policy workflow_step_library_read on "better_supabase"."workflow_step_library" for select to authenticated using (true);

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
revoke all on "better_supabase"."workflow_node_runs" from anon, authenticated;
grant select on "better_supabase"."workflow_node_runs" to authenticated;
grant all on "better_supabase"."workflow_node_runs" to service_role;
drop policy if exists workflow_node_runs_read on "better_supabase"."workflow_node_runs";
create policy workflow_node_runs_read on "better_supabase"."workflow_node_runs" for select to authenticated
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
revoke all on "better_supabase"."workflow_alerts" from anon, authenticated;
grant select on "better_supabase"."workflow_alerts" to authenticated;
grant all on "better_supabase"."workflow_alerts" to service_role;
drop policy if exists workflow_alerts_read on "better_supabase"."workflow_alerts";
create policy workflow_alerts_read on "better_supabase"."workflow_alerts" for select to authenticated
  using ("definition_id" in (select x."id" from "better_supabase"."workflow_definitions" x));

create table if not exists "better_supabase"."workflow_alert_fires" (
  "alert_id" uuid not null references "better_supabase"."workflow_alerts" ("id") on delete cascade,
  "run_id" uuid not null references "better_supabase"."workflow_runs" ("id") on delete cascade,
  "fired_at" timestamptz not null default now(),
  primary key ("alert_id", "run_id")
);
create index if not exists workflow_alert_fires_run_idx on "better_supabase"."workflow_alert_fires" ("run_id");
alter table "better_supabase"."workflow_alert_fires" enable row level security;
revoke all on "better_supabase"."workflow_alert_fires" from anon, authenticated;
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
  if v_triggers <> 1 then
    v_errors := array_append(v_errors, 'A graph has exactly one trigger node');
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
-- the service role or workflow.edit in tenant.
create or replace function "better_supabase"."save_workflow_definition"(
  tenant uuid,
  slug text,
  name text,
  description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_definitions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_definitions" as x ("tenant_id", "slug", "name", "description", "created_by")
  values (tenant, slug, name, description, (select auth.uid()))
  on conflict on constraint workflow_definitions_tenant_slug_key do update set
    "name" = excluded."name",
    "description" = excluded."description",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_definition"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_workflow_definition"(uuid, text, text, text) to authenticated, service_role;

-- The definitions the caller may read, by name, each with the number of its
-- published version and whether it has a draft.
create or replace function "better_supabase"."workflow_definitions_list"(tenant uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft')
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_definitions" x
  where workflow_definitions_list.tenant is null or x."tenant_id" = workflow_definitions_list.tenant;
$$;
revoke execute on function "better_supabase"."workflow_definitions_list"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_definitions_list"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."workflow_definition_get"(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) from "better_supabase"."workflow_definitions" x where x."id" = workflow_definition_get.definition;
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
  delete from "better_supabase"."workflow_definitions" x
  where x."id" = definition and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_definition"(uuid) to authenticated, service_role;

-- Saves graph as the definition's draft: updates the draft, or opens one
-- numbered after the last version. workflow.edit in its tenant.
create or replace function "better_supabase"."save_workflow_draft"(definition uuid, graph jsonb)
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
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
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
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$$;
revoke execute on function "better_supabase"."save_workflow_draft"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_workflow_draft"(uuid, jsonb) to authenticated, service_role;

-- Publishes a version: workflow.publish in its tenant, and a graph
-- validate_workflow_graph accepts. The version published before is
-- archived. Only the service role may store the engine's compiled form,
-- also on a version that is already published.
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
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
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
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set "status" = 'published', "compiled" = compiled, "published_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
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
    'publishedAt', x."published_at"
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
    'graph', x."graph",
    'compiled', x."compiled"
  ) from "better_supabase"."workflow_versions" x where x."id" = workflow_version_get.version;
$$;
revoke execute on function "better_supabase"."workflow_version_get"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_version_get"(uuid) to authenticated, service_role;

-- What a run of definition starts from: its tenant and its published
-- version. workflow.run in its tenant, or the service role.
create or replace function "better_supabase"."workflow_start_target"(definition uuid)
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
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.run'), false))) then
    raise exception 'You may not run this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."definition_id" = definition and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ), 'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  ));
end;
$$;
revoke execute on function "better_supabase"."workflow_start_target"(uuid) from public, anon;
grant execute on function "better_supabase"."workflow_start_target"(uuid) to authenticated, service_role;

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
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
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
  delete from "better_supabase"."workflow_triggers" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = trigger and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.edit'), false)));
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
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  select y."tenant_id", x."kind" into v_tenant, v_kind
  from "better_supabase"."workflow_triggers" x join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."id" = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
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

-- The enabled event triggers listening for type (config.type) in tenant,
-- with their definitions (service role; the outbox consumer calls it).
create or replace function "better_supabase"."workflow_event_targets"(type text, tenant uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('trigger', jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ), 'tenant', y."tenant_id") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_triggers" x
  join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."kind" = 'event' and x."enabled"
    and x."config" ->> 'type' = workflow_event_targets.type
    and y."tenant_id" is not distinct from workflow_event_targets.tenant;
$$;
revoke execute on function "better_supabase"."workflow_event_targets"(text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_event_targets"(text, uuid) to service_role;

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
-- description, inputSchema, outputSchema, credentialKind } }); returns how
-- many there are.
create or replace function "better_supabase"."sync_workflow_steps"(steps jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "better_supabase"."workflow_step_library" ("name", "title", "description", "input_schema", "output_schema", "credential_kind")
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce(e.value -> 'inputSchema', '{}'::jsonb), coalesce(e.value -> 'outputSchema', '{}'::jsonb), e.value ->> 'credentialKind'
  from jsonb_each(coalesce(steps, '{}'::jsonb)) e
  on conflict ("name") do update set
    "title" = excluded."title",
    "description" = excluded."description",
    "input_schema" = excluded."input_schema",
    "output_schema" = excluded."output_schema",
    "credential_kind" = excluded."credential_kind",
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
  delete from "better_supabase"."workflow_alerts" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = alert and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_workflow_alert"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_workflow_alert"(uuid) to authenticated, service_role;

-- Fires the failed alerts of a run's definition (the bs.definition
-- attribute) when the run fails.
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
  if new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bs.definition'
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
drop trigger if exists "bs_workflow_runs_alert" on "better_supabase"."workflow_runs";
create trigger "bs_workflow_runs_alert" after insert or update of "status" on "better_supabase"."workflow_runs"
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
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bs.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
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

-- sql.modules.workflow-builder.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."validate_workflow_graph"(graph jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."validate_workflow_graph"($1) $$;
revoke execute on function "api"."validate_workflow_graph"(jsonb) from public, anon;
grant execute on function "api"."validate_workflow_graph"(jsonb) to authenticated, service_role;

create or replace function "api"."save_workflow_definition"(tenant uuid, slug text, name text, description text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_workflow_definition"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_workflow_definition"(uuid, text, text, text) from public, anon;
grant execute on function "api"."save_workflow_definition"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."workflow_definitions_list"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_definitions_list"($1) $$;
revoke execute on function "api"."workflow_definitions_list"(uuid) from public, anon;
grant execute on function "api"."workflow_definitions_list"(uuid) to authenticated, service_role;

create or replace function "api"."workflow_definition_get"(definition uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_definition_get"($1) $$;
revoke execute on function "api"."workflow_definition_get"(uuid) from public, anon;
grant execute on function "api"."workflow_definition_get"(uuid) to authenticated, service_role;

create or replace function "api"."remove_workflow_definition"(definition uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_workflow_definition"($1) $$;
revoke execute on function "api"."remove_workflow_definition"(uuid) from public, anon;
grant execute on function "api"."remove_workflow_definition"(uuid) to authenticated, service_role;

create or replace function "api"."save_workflow_draft"(definition uuid, graph jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_workflow_draft"($1, $2) $$;
revoke execute on function "api"."save_workflow_draft"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_workflow_draft"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."publish_workflow_version"(version uuid, compiled jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_workflow_version"($1, $2) $$;
revoke execute on function "api"."publish_workflow_version"(uuid, jsonb) from public, anon;
grant execute on function "api"."publish_workflow_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."workflow_versions_list"(definition uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_versions_list"($1) $$;
revoke execute on function "api"."workflow_versions_list"(uuid) from public, anon;
grant execute on function "api"."workflow_versions_list"(uuid) to authenticated, service_role;

create or replace function "api"."workflow_version_get"(version uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_version_get"($1) $$;
revoke execute on function "api"."workflow_version_get"(uuid) from public, anon;
grant execute on function "api"."workflow_version_get"(uuid) to authenticated, service_role;

create or replace function "api"."workflow_start_target"(definition uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_start_target"($1) $$;
revoke execute on function "api"."workflow_start_target"(uuid) from public, anon;
grant execute on function "api"."workflow_start_target"(uuid) to authenticated, service_role;

create or replace function "api"."save_workflow_trigger"(definition uuid, kind text, config jsonb default '{}'::jsonb, enabled boolean default true, trigger uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_workflow_trigger"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) from public, anon;
grant execute on function "api"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) to authenticated, service_role;

create or replace function "api"."workflow_triggers_list"(definition uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_triggers_list"($1) $$;
revoke execute on function "api"."workflow_triggers_list"(uuid) from public, anon;
grant execute on function "api"."workflow_triggers_list"(uuid) to authenticated, service_role;

create or replace function "api"."remove_workflow_trigger"(trigger uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_workflow_trigger"($1) $$;
revoke execute on function "api"."remove_workflow_trigger"(uuid) from public, anon;
grant execute on function "api"."remove_workflow_trigger"(uuid) to authenticated, service_role;

create or replace function "api"."rotate_workflow_webhook_token"(trigger uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_workflow_webhook_token"($1) $$;
revoke execute on function "api"."rotate_workflow_webhook_token"(uuid) from public, anon;
grant execute on function "api"."rotate_workflow_webhook_token"(uuid) to authenticated, service_role;

create or replace function "api"."workflow_webhook_target"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_webhook_target"($1) $$;
revoke execute on function "api"."workflow_webhook_target"(text) from public, anon, authenticated;
grant execute on function "api"."workflow_webhook_target"(text) to service_role;

create or replace function "api"."workflow_event_targets"(type text, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_event_targets"($1, $2) $$;
revoke execute on function "api"."workflow_event_targets"(text, uuid) from public, anon, authenticated;
grant execute on function "api"."workflow_event_targets"(text, uuid) to service_role;

create or replace function "api"."save_workflow_credential"(tenant uuid, kind text, name text, ref jsonb, scopes text[] default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_workflow_credential"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_workflow_credential"(uuid, text, text, jsonb, text[]) from public, anon;
grant execute on function "api"."save_workflow_credential"(uuid, text, text, jsonb, text[]) to authenticated, service_role;

create or replace function "api"."workflow_credentials_list"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_credentials_list"($1) $$;
revoke execute on function "api"."workflow_credentials_list"(uuid) from public, anon;
grant execute on function "api"."workflow_credentials_list"(uuid) to authenticated, service_role;

create or replace function "api"."workflow_credential_get"(credential uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_credential_get"($1) $$;
revoke execute on function "api"."workflow_credential_get"(uuid) from public, anon, authenticated;
grant execute on function "api"."workflow_credential_get"(uuid) to service_role;

create or replace function "api"."remove_workflow_credential"(credential uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_workflow_credential"($1) $$;
revoke execute on function "api"."remove_workflow_credential"(uuid) from public, anon;
grant execute on function "api"."remove_workflow_credential"(uuid) to authenticated, service_role;

create or replace function "api"."sync_workflow_steps"(steps jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sync_workflow_steps"($1) $$;
revoke execute on function "api"."sync_workflow_steps"(jsonb) from public, anon, authenticated;
grant execute on function "api"."sync_workflow_steps"(jsonb) to service_role;

create or replace function "api"."workflow_steps_list"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_steps_list"() $$;
revoke execute on function "api"."workflow_steps_list"() from public, anon;
grant execute on function "api"."workflow_steps_list"() to authenticated, service_role;

create or replace function "api"."record_workflow_node_run"(run text, node text, status text, attempt integer default null, output jsonb default null, error text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_workflow_node_run"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text) to service_role;

create or replace function "api"."workflow_node_runs_list"(run text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_node_runs_list"($1) $$;
revoke execute on function "api"."workflow_node_runs_list"(text) from public, anon;
grant execute on function "api"."workflow_node_runs_list"(text) to authenticated, service_role;

create or replace function "api"."save_workflow_alert"(definition uuid, on_event text, channel jsonb default '{}'::jsonb, threshold interval default null, alert uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_workflow_alert"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) from public, anon;
grant execute on function "api"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) to authenticated, service_role;

create or replace function "api"."workflow_alerts_list"(definition uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_alerts_list"($1) $$;
revoke execute on function "api"."workflow_alerts_list"(uuid) from public, anon;
grant execute on function "api"."workflow_alerts_list"(uuid) to authenticated, service_role;

create or replace function "api"."remove_workflow_alert"(alert uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_workflow_alert"($1) $$;
revoke execute on function "api"."remove_workflow_alert"(uuid) from public, anon;
grant execute on function "api"."remove_workflow_alert"(uuid) to authenticated, service_role;

create or replace function "api"."check_workflow_alerts"(batch integer default 100)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_workflow_alerts"($1) $$;
revoke execute on function "api"."check_workflow_alerts"(integer) from public, anon, authenticated;
grant execute on function "api"."check_workflow_alerts"(integer) to service_role;

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
