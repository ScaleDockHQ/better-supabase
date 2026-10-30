-- ==== alone: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:de5cc24630e4d748185948ee70ef360afaab19160c05d88759f9e9501a7e3834
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

create table if not exists "better_supabase"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from public, anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists control_frameworks_read on "better_supabase"."control_frameworks";
create policy control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text check ("source" is null or length("source") between 1 and 200),
  "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "better_supabase"."control_frameworks" ("tenant_id", "id") on delete cascade
);
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from public, anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists controls_read on "better_supabase"."controls";
create policy controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null check ("interval_days" between 1 and 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
revoke all on "better_supabase"."evidence_tasks" from public, anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists evidence_tasks_read on "better_supabase"."evidence_tasks";
create policy evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid,
  "note" text check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  check ("attachment_id" is not null or "note" is not null),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
revoke all on "better_supabase"."control_evidence" from public, anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists control_evidence_read on "better_supabase"."control_evidence";
create policy control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index if not exists "policies_version_idx" on "better_supabase"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."policies" enable row level security;
revoke all on "better_supabase"."policies" from public, anon, authenticated;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists policies_read on "better_supabase"."policies";
create policy policies_read on "better_supabase"."policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

create table if not exists "better_supabase"."policy_acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "policy_id" uuid not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "acknowledged_at" timestamptz not null default now(),
  unique ("policy_id", "version_id", "user_id"),
  foreign key ("tenant_id", "policy_id") references "better_supabase"."policies" ("tenant_id", "id") on delete cascade
);
create index if not exists "policy_acknowledgements_user_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "better_supabase"."policy_acknowledgements" ("version_id");
alter table "better_supabase"."policy_acknowledgements" enable row level security;
revoke all on "better_supabase"."policy_acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists policy_acknowledgements_read on "better_supabase"."policy_acknowledgements";
create policy policy_acknowledgements_read on "better_supabase"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    null;
    
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
create policy bsb_tenant_scope_select on "better_supabase"."policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
create policy bsb_tenant_scope_insert on "better_supabase"."policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
create policy bsb_tenant_scope_update on "better_supabase"."policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
create policy bsb_tenant_scope_delete on "better_supabase"."policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:a2e4b2323ab82894622f551ade6096a98698cb06059a01e883297d503f278090
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:cd7f814937ea84b53c313363491545690248618e5009aecaf8931f887ad0c25a
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

create table if not exists "better_supabase"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from public, anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists control_frameworks_read on "better_supabase"."control_frameworks";
create policy control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text check ("source" is null or length("source") between 1 and 200),
  "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "better_supabase"."control_frameworks" ("tenant_id", "id") on delete cascade
);
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from public, anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists controls_read on "better_supabase"."controls";
create policy controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null check ("interval_days" between 1 and 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
revoke all on "better_supabase"."evidence_tasks" from public, anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists evidence_tasks_read on "better_supabase"."evidence_tasks";
create policy evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid references "better_supabase"."attachments" ("id") on delete cascade,
  "note" text check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  check ("attachment_id" is not null or "note" is not null),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
revoke all on "better_supabase"."control_evidence" from public, anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists control_evidence_read on "better_supabase"."control_evidence";
create policy control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index if not exists "policies_version_idx" on "better_supabase"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."policies" enable row level security;
revoke all on "better_supabase"."policies" from public, anon, authenticated;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists policies_read on "better_supabase"."policies";
create policy policies_read on "better_supabase"."policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

create table if not exists "better_supabase"."policy_acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "policy_id" uuid not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "acknowledged_at" timestamptz not null default now(),
  unique ("policy_id", "version_id", "user_id"),
  foreign key ("tenant_id", "policy_id") references "better_supabase"."policies" ("tenant_id", "id") on delete cascade
);
create index if not exists "policy_acknowledgements_user_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "better_supabase"."policy_acknowledgements" ("version_id");
alter table "better_supabase"."policy_acknowledgements" enable row level security;
revoke all on "better_supabase"."policy_acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists policy_acknowledgements_read on "better_supabase"."policy_acknowledgements";
create policy policy_acknowledgements_read on "better_supabase"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    perform "better_supabase".emit_event('control.created', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.created',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'created control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  else
    perform "better_supabase".emit_event('control.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.updated',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'updated control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = add_control_evidence.attachment_id
      and a."organization_id" = v_control."tenant_id"
  ) then
    raise exception 'the attachment isn''t a file in this organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  perform "better_supabase".emit_event('control.evidence_added', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id"), 'controls/' || v_row."control_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.evidence_added',
    category => 'data',
    target_type => 'control',
    record_id => v_row."control_id"::text,
    summary => 'collected evidence for control ' || v_control."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    perform "better_supabase".emit_event('evidence_task.missed', jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on"), 'evidence-tasks/' || v_task."id"::text, (v_task."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'evidence_task.missed',
    category => 'data',
    target_type => 'evidence_task',
    record_id => v_task."id"::text,
    summary => 'evidence task overdue: ' || v_task."title",
    tenant => (v_task."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on")
  );
    if coalesce(v_task."assignee_id", v_owner) is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task."tenant_id",
        'actor', null,
        'subject_type', 'control',
        'subject_id', v_task."control_id"::text,
        'summary', v_task."title",
        'recipients', to_jsonb(array[coalesce(v_task."assignee_id", v_owner)]),
        'key', 'evidence_task.missed:' || v_task."id"::text || ':' || v_task."due_on"::text,
        'data', jsonb_build_object('evidenceTaskId', v_task."id", 'dueOn', v_task."due_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('compliance_policy.published', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number"), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'compliance_policy.published',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'published policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    perform "better_supabase".emit_event('compliance_policy.acknowledged', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'compliance_policy.acknowledged',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'acknowledged policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me)
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
create policy bsb_tenant_scope_select on "better_supabase"."policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
create policy bsb_tenant_scope_insert on "better_supabase"."policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
create policy bsb_tenant_scope_update on "better_supabase"."policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
create policy bsb_tenant_scope_delete on "better_supabase"."policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:4a8ca08ae1243dc1aa52aa73660999d4cc602cf6b99736b57a46c50697193620
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_subscriptions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_subscriptions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."incoming_webhooks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."incoming_webhooks" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."guest_grants"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."guest_grants" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."attachments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."attachments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."enrollments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."taggings"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."taggings" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_history" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_stages"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_stages" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_lifecycles"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_lifecycles" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."share_links"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."share_links" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_views"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_views" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_user_state"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_user_state" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."recurrence_rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."recurrence_rules" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reminders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reminders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."relations" set "source_type" = 'compliance_policy' where "source_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."relations" set "target_type" = 'compliance_policy' where "target_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bulk_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."bulk_runs" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."search_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."search_documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."trash_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."trash_items" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reactions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reactions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reaction_scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reaction_scores" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_policies" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."documents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."form_submissions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."form_submissions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."signature_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."signature_requests" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."template_applications"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."template_applications" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_policies" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_clocks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_clocks" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collections"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collections" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collection_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collection_entries" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."favorites"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."favorites" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."saved_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."saved_items" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."moderation_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."moderation_items" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reviews"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reviews" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."review_stats"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."review_stats" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."rules" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."rule_defaults"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."rule_defaults" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."rule_evaluations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."rule_evaluations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."rule_fields"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."rule_fields" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."score_models"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."score_models" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."scores" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."work_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."work_orders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."conversations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."conversations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."message_record_mentions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."message_record_mentions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."activity_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."activity_entries" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."mail_thread_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."mail_thread_subjects" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."segments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."segments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignment_queues"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignment_queues" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_changes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_changes" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sequence_enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sequence_enrollments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."lead_score_checks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."lead_score_checks" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."qualification_requirements"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."qualification_requirements" set "target_type" = 'compliance_policy' where "target_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgements"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgements" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_notices"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_notices" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."consents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."consents" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."observations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."observations" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."medication_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."medication_orders" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_plans"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_plans" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:d5df719cf6b29f5ed3f1dfe11bea04ecd3e114e88010fbb99eeab3a42c9e3872
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "app_private"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "app_private"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "app_private"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."controls";
    drop policy if exists bsb_tenant_scope_select on "app_private"."controls";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."controls";
    drop policy if exists bsb_tenant_scope_update on "app_private"."controls";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "app_private"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "app_private"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "app_private"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "app_private"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."policies";
    drop policy if exists bsb_tenant_scope_select on "app_private"."policies";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."policies";
    drop policy if exists bsb_tenant_scope_update on "app_private"."policies";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "app_private"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "app_private"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

create table if not exists "app_private"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "app_private"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "app_private"."control_frameworks" enable row level security;
revoke all on "app_private"."control_frameworks" from public, anon, authenticated;
grant select on "app_private"."control_frameworks" to authenticated;
grant all on "app_private"."control_frameworks" to service_role;
drop policy if exists control_frameworks_read on "app_private"."control_frameworks";
create policy control_frameworks_read on "app_private"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "app_private"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text check ("source" is null or length("source") between 1 and 200),
  "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "app_private"."control_frameworks" ("tenant_id", "id") on delete cascade
);
alter table "app_private"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "app_private"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create index if not exists "controls_tenant_idx" on "app_private"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "app_private"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "app_private"."controls" enable row level security;
revoke all on "app_private"."controls" from public, anon, authenticated;
grant select on "app_private"."controls" to authenticated;
grant all on "app_private"."controls" to service_role;
drop policy if exists controls_read on "app_private"."controls";
create policy controls_read on "app_private"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "app_private"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null check ("interval_days" between 1 and 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "control_id") references "app_private"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "evidence_tasks_parent_idx" on "app_private"."evidence_tasks" ("tenant_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "app_private"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "app_private"."evidence_tasks" ("due_on") where "active";
alter table "app_private"."evidence_tasks" enable row level security;
revoke all on "app_private"."evidence_tasks" from public, anon, authenticated;
grant select on "app_private"."evidence_tasks" to authenticated;
grant all on "app_private"."evidence_tasks" to service_role;
drop policy if exists evidence_tasks_read on "app_private"."evidence_tasks";
create policy evidence_tasks_read on "app_private"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "app_private"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "app_private"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid,
  "note" text check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  check ("attachment_id" is not null or "note" is not null),
  foreign key ("tenant_id", "control_id") references "app_private"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "control_evidence_parent_idx" on "app_private"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "app_private"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "app_private"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "app_private"."control_evidence" enable row level security;
revoke all on "app_private"."control_evidence" from public, anon, authenticated;
grant select on "app_private"."control_evidence" to authenticated;
grant all on "app_private"."control_evidence" to service_role;
drop policy if exists control_evidence_read on "app_private"."control_evidence";
create policy control_evidence_read on "app_private"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "app_private"."policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index if not exists "policies_version_idx" on "app_private"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "app_private"."policies" enable row level security;
revoke all on "app_private"."policies" from public, anon, authenticated;
grant select on "app_private"."policies" to authenticated;
grant all on "app_private"."policies" to service_role;
drop policy if exists policies_read on "app_private"."policies";
create policy policies_read on "app_private"."policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

create table if not exists "app_private"."policy_acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "policy_id" uuid not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "acknowledged_at" timestamptz not null default now(),
  unique ("policy_id", "version_id", "user_id"),
  foreign key ("tenant_id", "policy_id") references "app_private"."policies" ("tenant_id", "id") on delete cascade
);
create index if not exists "policy_acknowledgements_user_idx" on "app_private"."policy_acknowledgements" ("tenant_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "app_private"."policy_acknowledgements" ("tenant_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "app_private"."policy_acknowledgements" ("version_id");
alter table "app_private"."policy_acknowledgements" enable row level security;
revoke all on "app_private"."policy_acknowledgements" from public, anon, authenticated;
grant select on "app_private"."policy_acknowledgements" to authenticated;
grant all on "app_private"."policy_acknowledgements" to service_role;
drop policy if exists policy_acknowledgements_read on "app_private"."policy_acknowledgements";
create policy policy_acknowledgements_read on "app_private"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "app_private"."save_control_framework"(uuid, text, text, text, text);
create or replace function "app_private"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "app_private"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "app_private"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "app_private"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "app_private"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "app_private"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "app_private"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "app_private"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "app_private"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "app_private"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "app_private"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "app_private"."control_frameworks"%rowtype;
  v_row "app_private"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "app_private"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "app_private"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "app_private"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "app_private"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "app_private"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "app_private"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "app_private"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."controls"%rowtype;
begin
  select * into v_row from "app_private"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "app_private"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "app_private"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "app_private"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "app_private"."get_control"(uuid) from public, anon;
grant execute on function "app_private"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "app_private"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "app_private"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "app_private"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "app_private"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "app_private"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "app_private"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "app_private"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "app_private"."controls"%rowtype;
  v_task "app_private"."evidence_tasks"%rowtype;
  v_row "app_private"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "app_private"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "app_private"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "app_private"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "app_private"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "app_private"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "app_private"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "app_private"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "app_private"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "app_private"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "app_private"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "app_private"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "app_private"."controls"%rowtype;
  v_row "app_private"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "app_private"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "app_private"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "app_private"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "app_private"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "app_private"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "app_private"."evidence_tasks" x
  join "app_private"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "app_private"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "app_private"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "app_private"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "app_private"."evidence_tasks" ot join "app_private"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "app_private"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "app_private"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "app_private"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "app_private"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "app_private"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "app_private"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "app_private"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "app_private"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "app_private"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "app_private"."controls" y where y."id" = v_task."control_id";
    null;
    
    update "app_private"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "app_private"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "app_private"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "app_private"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "app_private"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "app_private"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "app_private"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "app_private"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "app_private"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "app_private"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "app_private"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "app_private"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "app_private"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "app_private"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "app_private"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "app_private"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "app_private"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "app_private"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "app_private"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "app_private"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "app_private"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "app_private"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "app_private"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "app_private"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "app_private"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "app_private"."policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "app_private"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "app_private"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "app_private"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "app_private"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."policies"%rowtype;
begin
  select * into v_row from "app_private"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "app_private"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "app_private"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "app_private"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "app_private"."control_frameworks";
create policy bsb_tenant_scope_select on "app_private"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."control_frameworks";
create policy bsb_tenant_scope_insert on "app_private"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."control_frameworks";
create policy bsb_tenant_scope_update on "app_private"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."control_frameworks";
create policy bsb_tenant_scope_delete on "app_private"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."controls";
drop policy if exists bsb_tenant_scope_select on "app_private"."controls";
create policy bsb_tenant_scope_select on "app_private"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."controls";
create policy bsb_tenant_scope_insert on "app_private"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."controls";
create policy bsb_tenant_scope_update on "app_private"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."controls";
create policy bsb_tenant_scope_delete on "app_private"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "app_private"."control_evidence";
create policy bsb_tenant_scope_select on "app_private"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."control_evidence";
create policy bsb_tenant_scope_insert on "app_private"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."control_evidence";
create policy bsb_tenant_scope_update on "app_private"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."control_evidence";
create policy bsb_tenant_scope_delete on "app_private"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "app_private"."evidence_tasks";
create policy bsb_tenant_scope_select on "app_private"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."evidence_tasks";
create policy bsb_tenant_scope_insert on "app_private"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."evidence_tasks";
create policy bsb_tenant_scope_update on "app_private"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."evidence_tasks";
create policy bsb_tenant_scope_delete on "app_private"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."policies";
drop policy if exists bsb_tenant_scope_select on "app_private"."policies";
create policy bsb_tenant_scope_select on "app_private"."policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."policies";
create policy bsb_tenant_scope_insert on "app_private"."policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."policies";
create policy bsb_tenant_scope_update on "app_private"."policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."policies";
create policy bsb_tenant_scope_delete on "app_private"."policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "app_private"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "app_private"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "app_private"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "app_private"."policy_acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "app_private"."policy_acknowledgements" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:a2e4b2323ab82894622f551ade6096a98698cb06059a01e883297d503f278090
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:07563a1e837381bce0ac1c6a839ff584b18dd3ffd3a6aea0544aa056ac7bf3e0
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

create table if not exists "better_supabase"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from public, anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists control_frameworks_read on "better_supabase"."control_frameworks";
create policy control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text check ("source" is null or length("source") between 1 and 200),
  "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "better_supabase"."control_frameworks" ("tenant_id", "id") on delete cascade
);
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from public, anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists controls_read on "better_supabase"."controls";
create policy controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null check ("interval_days" between 1 and 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
revoke all on "better_supabase"."evidence_tasks" from public, anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists evidence_tasks_read on "better_supabase"."evidence_tasks";
create policy evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid,
  "note" text check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  check ("attachment_id" is not null or "note" is not null),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index if not exists "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
revoke all on "better_supabase"."control_evidence" from public, anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists control_evidence_read on "better_supabase"."control_evidence";
create policy control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index if not exists "policies_version_idx" on "better_supabase"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."policies" enable row level security;
revoke all on "better_supabase"."policies" from public, anon, authenticated;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists policies_read on "better_supabase"."policies";
create policy policies_read on "better_supabase"."policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

create table if not exists "better_supabase"."policy_acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "policy_id" uuid not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "acknowledged_at" timestamptz not null default now(),
  unique ("policy_id", "version_id", "user_id"),
  foreign key ("tenant_id", "policy_id") references "better_supabase"."policies" ("tenant_id", "id") on delete cascade
);
create index if not exists "policy_acknowledgements_user_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "better_supabase"."policy_acknowledgements" ("version_id");
alter table "better_supabase"."policy_acknowledgements" enable row level security;
revoke all on "better_supabase"."policy_acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists policy_acknowledgements_read on "better_supabase"."policy_acknowledgements";
create policy policy_acknowledgements_read on "better_supabase"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    null;
    
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
create policy bsb_tenant_scope_select on "better_supabase"."policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
create policy bsb_tenant_scope_insert on "better_supabase"."policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
create policy bsb_tenant_scope_update on "better_supabase"."policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
create policy bsb_tenant_scope_delete on "better_supabase"."policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.compliance.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_control_framework"(uuid, text, text, text, text);
drop function if exists "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);

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

create or replace function "api"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_control_framework"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "api"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_control_frameworks"($1) $$;
revoke execute on function "api"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "api"."list_control_frameworks"(uuid) to authenticated, service_role;

create or replace function "api"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_control"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_control"(control_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_control"($1) $$;
revoke execute on function "api"."get_control"(uuid) from public, anon;
grant execute on function "api"."get_control"(uuid) to authenticated, service_role;

create or replace function "api"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_controls"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_control_evidence"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "api"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "api"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_control_evidence"($1) $$;
revoke execute on function "api"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "api"."remove_control_evidence"(uuid) to authenticated, service_role;

create or replace function "api"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_evidence_task"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_evidence_tasks"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."control_posture"($1, $2) $$;
revoke execute on function "api"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "api"."control_posture"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."notify_overdue_evidence_tasks"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_overdue_evidence_tasks"() $$;
revoke execute on function "api"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "api"."notify_overdue_evidence_tasks"() to service_role;

create or replace function "api"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_compliance_policy"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "api"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_compliance_policy"($1, $2, $3) $$;
revoke execute on function "api"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_compliance_policy"($1) $$;
revoke execute on function "api"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "api"."archive_compliance_policy"(uuid) to authenticated, service_role;

create or replace function "api"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acknowledge_compliance_policy"($1) $$;
revoke execute on function "api"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "api"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

create or replace function "api"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_compliance_policies"($1, $2, $3) $$;
revoke execute on function "api"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "api"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

create or replace function "api"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."compliance_policy_acknowledgements"($1) $$;
revoke execute on function "api"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "api"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:a2e4b2323ab82894622f551ade6096a98698cb06059a01e883297d503f278090
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:0becf8cc6611014d038b25daf5f14c696742094597a4f8db837bbc7b549f32a3
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

-- better_supabase.control_frameworks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."control_frameworks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."control_frameworks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."control_frameworks" add column if not exists "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$');
alter table "better_supabase"."control_frameworks" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "better_supabase"."control_frameworks" add column if not exists "version" text check ("version" is null or length("version") <= 50);
alter table "better_supabase"."control_frameworks" add column if not exists "description" text check ("description" is null or length("description") <= 4000);
alter table "better_supabase"."control_frameworks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."control_frameworks" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
create unique index if not exists "bsb_control_frameworks_tenant_key_key" on "better_supabase"."control_frameworks" ("tenant_id", "key");
create unique index if not exists "bsb_control_frameworks_tenant_id_key" on "better_supabase"."control_frameworks" ("tenant_id", "id");
alter table "better_supabase"."control_frameworks" enable row level security;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists bsb_control_frameworks_read on "better_supabase"."control_frameworks";
create policy bsb_control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- better_supabase.controls is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."controls" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."controls" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."controls" add column if not exists "framework_id" uuid;
alter table "better_supabase"."controls" add column if not exists "code" text check (length("code") between 1 and 50);
alter table "better_supabase"."controls" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "description" text check ("description" is null or length("description") <= 10000);
alter table "better_supabase"."controls" add column if not exists "owner_id" uuid;
alter table "better_supabase"."controls" add column if not exists "applicable" boolean not null default true;
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."controls" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create unique index if not exists "bsb_controls_framework_code_key" on "better_supabase"."controls" ("framework_id", "code");
create unique index if not exists "bsb_controls_tenant_id_key" on "better_supabase"."controls" ("tenant_id", "id");
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists bsb_controls_read on "better_supabase"."controls";
create policy bsb_controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- better_supabase.evidence_tasks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."evidence_tasks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."evidence_tasks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."evidence_tasks" add column if not exists "control_id" uuid;
alter table "better_supabase"."evidence_tasks" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."evidence_tasks" add column if not exists "assignee_id" uuid;
alter table "better_supabase"."evidence_tasks" add column if not exists "interval_days" integer check ("interval_days" between 1 and 3650);
alter table "better_supabase"."evidence_tasks" add column if not exists "due_on" date;
alter table "better_supabase"."evidence_tasks" add column if not exists "last_collected_at" timestamptz;
alter table "better_supabase"."evidence_tasks" add column if not exists "notified_for" date;
alter table "better_supabase"."evidence_tasks" add column if not exists "active" boolean not null default true;
alter table "better_supabase"."evidence_tasks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."evidence_tasks" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists bsb_evidence_tasks_read on "better_supabase"."evidence_tasks";
create policy bsb_evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- better_supabase.control_evidence is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."control_evidence" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."control_evidence" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."control_evidence" add column if not exists "control_id" uuid;
alter table "better_supabase"."control_evidence" add column if not exists "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null;
alter table "better_supabase"."control_evidence" add column if not exists "attachment_id" uuid;
alter table "better_supabase"."control_evidence" add column if not exists "note" text check ("note" is null or length("note") <= 4000);
alter table "better_supabase"."control_evidence" add column if not exists "collected_by" uuid;
alter table "better_supabase"."control_evidence" add column if not exists "collected_at" timestamptz not null default now();
alter table "better_supabase"."control_evidence" add column if not exists "valid_until" date;
create index if not exists "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists bsb_control_evidence_read on "better_supabase"."control_evidence";
create policy bsb_control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- better_supabase.policies is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."policies" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."policies" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."policies" add column if not exists "key" text check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$');
alter table "better_supabase"."policies" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."policies" add column if not exists "owner_id" uuid;
alter table "better_supabase"."policies" add column if not exists "requires_acknowledgement" boolean not null default true;
alter table "better_supabase"."policies" add column if not exists "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict;
alter table "better_supabase"."policies" add column if not exists "version_number" integer;
alter table "better_supabase"."policies" add column if not exists "published_at" timestamptz;
alter table "better_supabase"."policies" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."policies" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."policies" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_policies_tenant_key_key" on "better_supabase"."policies" ("tenant_id", "key");
create unique index if not exists "bsb_policies_tenant_id_key" on "better_supabase"."policies" ("tenant_id", "id");
create index if not exists "policies_version_idx" on "better_supabase"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."policies" enable row level security;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists bsb_policies_read on "better_supabase"."policies";
create policy bsb_policies_read on "better_supabase"."policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

-- better_supabase.policy_acknowledgements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."policy_acknowledgements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."policy_acknowledgements" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."policy_acknowledgements" add column if not exists "policy_id" uuid;
alter table "better_supabase"."policy_acknowledgements" add column if not exists "version_id" uuid references "better_supabase"."versions" ("id") on delete restrict;
alter table "better_supabase"."policy_acknowledgements" add column if not exists "user_id" uuid;
alter table "better_supabase"."policy_acknowledgements" add column if not exists "acknowledged_at" timestamptz not null default now();
create unique index if not exists "bsb_policy_acknowledgements_policy_version_user_key" on "better_supabase"."policy_acknowledgements" ("policy_id", "version_id", "user_id");
create index if not exists "policy_acknowledgements_user_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "better_supabase"."policy_acknowledgements" ("version_id");
alter table "better_supabase"."policy_acknowledgements" enable row level security;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists bsb_policy_acknowledgements_read on "better_supabase"."policy_acknowledgements";
create policy bsb_policy_acknowledgements_read on "better_supabase"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    null;
    
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."organization_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
create policy bsb_tenant_scope_select on "better_supabase"."policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
create policy bsb_tenant_scope_insert on "better_supabase"."policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
create policy bsb_tenant_scope_update on "better_supabase"."policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
create policy bsb_tenant_scope_delete on "better_supabase"."policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:a2e4b2323ab82894622f551ade6096a98698cb06059a01e883297d503f278090
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:2d22d86213f2664c8ec736212eeae7c45e71c319a11b9e1fa90b2665b7c79e87
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge.

create table if not exists "better_supabase"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  unique ("org_id", "id")
);
alter table "better_supabase"."control_frameworks" add column if not exists "kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'));
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from public, anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists control_frameworks_read on "better_supabase"."control_frameworks";
create policy control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text check ("source" is null or length("source") between 1 and 200),
  "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("org_id", "id"),
  foreign key ("org_id", "framework_id") references "better_supabase"."control_frameworks" ("org_id", "id") on delete cascade
);
alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);
alter table "better_supabase"."controls" add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("org_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("org_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from public, anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists controls_read on "better_supabase"."controls";
create policy controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null check ("interval_days" between 1 and 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("org_id", "control_id") references "better_supabase"."controls" ("org_id", "id") on delete cascade
);
create index if not exists "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("org_id", "control_id");
create index if not exists "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("org_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index if not exists "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
revoke all on "better_supabase"."evidence_tasks" from public, anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists evidence_tasks_read on "better_supabase"."evidence_tasks";
create policy evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid,
  "note" text check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  check ("attachment_id" is not null or "note" is not null),
  foreign key ("org_id", "control_id") references "better_supabase"."controls" ("org_id", "id") on delete cascade
);
create index if not exists "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("org_id", "control_id", "collected_at" desc);
create index if not exists "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index if not exists "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
revoke all on "better_supabase"."control_evidence" from public, anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists control_evidence_read on "better_supabase"."control_evidence";
create policy control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table if not exists "better_supabase"."policies" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  unique ("org_id", "id")
);
create index if not exists "policies_version_idx" on "better_supabase"."policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."policies" enable row level security;
revoke all on "better_supabase"."policies" from public, anon, authenticated;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists policies_read on "better_supabase"."policies";
create policy policies_read on "better_supabase"."policies"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "org_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')));

create table if not exists "better_supabase"."policy_acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "policy_id" uuid not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "acknowledged_at" timestamptz not null default now(),
  unique ("policy_id", "version_id", "user_id"),
  foreign key ("org_id", "policy_id") references "better_supabase"."policies" ("org_id", "id") on delete cascade
);
create index if not exists "policy_acknowledgements_user_idx" on "better_supabase"."policy_acknowledgements" ("org_id", "user_id");
create index if not exists "policy_acknowledgements_parent_idx" on "better_supabase"."policy_acknowledgements" ("org_id", "policy_id");
create index if not exists "policy_acknowledgements_version_idx" on "better_supabase"."policy_acknowledgements" ("version_id");
alter table "better_supabase"."policy_acknowledgements" enable row level security;
revoke all on "better_supabase"."policy_acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists policy_acknowledgements_read on "better_supabase"."policy_acknowledgements";
create policy policy_acknowledgements_read on "better_supabase"."policy_acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("org_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("org_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."org_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."org_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."org_id" = v_framework."org_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("org_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."org_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."org_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."org_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("org_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."org_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."org_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."org_id" = v_control."org_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("org_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."org_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."org_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."org_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    null;
    
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."org_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."policies" ("org_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("org_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."org_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."org_id" = ack."org_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."org_id" = v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."org_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."org_id" = ack."org_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."org_id" = v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."org_id" = ack."org_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."org_id" = v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."org_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("org_id", "policy_id", "version_id", "user_id")
  values (v_row."org_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."org_id" = ack."org_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."org_id" = v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."org_id" = ack."org_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."org_id" = x."org_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."org_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."compliance_policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = compliance_policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'versionId', v_row."current_version_id",
    'versionNumber', v_row."version_number",
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m."user_id", 'acknowledgedAt', ack."acknowledged_at")
        order by ack."acknowledged_at" nulls first, m."user_id"), '[]'::jsonb)
      from "better_supabase"."memberships" m
      left join "better_supabase"."policy_acknowledgements" ack on ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = m."user_id"
      where m."org_id" = v_row."org_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."compliance_policy_acknowledgements"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."controls";
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."controls";
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."controls";
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."controls";
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."control_evidence";
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policies";
create policy bsb_tenant_scope_select on "better_supabase"."policies" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('compliance.read')) or "org_id" in (select better_supabase.tenant_ids_with('compliance.acknowledge')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policies";
create policy bsb_tenant_scope_insert on "better_supabase"."policies" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policies";
create policy bsb_tenant_scope_update on "better_supabase"."policies" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policies";
create policy bsb_tenant_scope_delete on "better_supabase"."policies" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."policy_acknowledgements" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."policy_acknowledgements" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."policy_acknowledgements" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."policy_acknowledgements" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:a2e4b2323ab82894622f551ade6096a98698cb06059a01e883297d503f278090
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'compliance_policy' where "subject_type" = 'policy'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
