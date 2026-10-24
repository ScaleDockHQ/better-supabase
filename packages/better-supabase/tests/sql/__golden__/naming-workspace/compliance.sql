-- ==== schema supabase/schemas/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block compliance@1 managed
-- @bsb-hash sha256:98cd27236e39aab94d555f3ca36883f40ec19b0d1e0112c48bb4d5d0f23c3960
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
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
  exception when undefined_table then null;
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
  "version" text check ("version" is null or length("version") <= 50),
  "description" text check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
drop policy if exists "control_frameworks_read" on "better_supabase"."control_frameworks";
create policy "control_frameworks_read" on "better_supabase"."control_frameworks" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')));

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
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "better_supabase"."control_frameworks" ("tenant_id", "id") on delete cascade
);
create index if not exists "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index if not exists "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
drop policy if exists "controls_read" on "better_supabase"."controls";
create policy "controls_read" on "better_supabase"."controls" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')));

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
revoke all on "better_supabase"."evidence_tasks" from anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
drop policy if exists "evidence_tasks_read" on "better_supabase"."evidence_tasks";
create policy "evidence_tasks_read" on "better_supabase"."evidence_tasks" for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.read')));

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
revoke all on "better_supabase"."control_evidence" from anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
drop policy if exists "control_evidence_read" on "better_supabase"."control_evidence";
create policy "control_evidence_read" on "better_supabase"."control_evidence" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')));

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
revoke all on "better_supabase"."policies" from anon, authenticated;
grant select on "better_supabase"."policies" to authenticated;
grant all on "better_supabase"."policies" to service_role;
drop policy if exists "policies_read" on "better_supabase"."policies";
create policy "policies_read" on "better_supabase"."policies" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.acknowledge')));

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
revoke all on "better_supabase"."policy_acknowledgements" from anon, authenticated;
grant select on "better_supabase"."policy_acknowledgements" to authenticated;
grant all on "better_supabase"."policy_acknowledgements" to service_role;
drop policy if exists "policy_acknowledgements_read" on "better_supabase"."policy_acknowledgements";
create policy "policy_acknowledgements_read" on "better_supabase"."policy_acknowledgements" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, jsonb);
create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."workspace_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.control_id is null then
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid) to authenticated, service_role;

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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'status', case
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
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'status', case
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
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'controls.collect'), false)) or (v_task."assignee_id" is not null and v_task."assignee_id" = auth.uid())) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null then
    raise exception 'evidence files need the attachments module' using errcode = '22023', hint = 'CONTROLS_INVALID';
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "better_supabase"."memberships" m where m."workspace_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
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
-- versions publish_policy writes.
create or replace function "better_supabase"."save_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_policy.tenant, 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if save_policy.owner_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m where m."workspace_id" = save_policy.tenant and m."user_id" = save_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'POLICY_INVALID';
  end if;
  if save_policy.policy_id is null then
    insert into "better_supabase"."policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_policy.tenant, save_policy.key, trim(save_policy.title), save_policy.owner_id, coalesce(save_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."policies" x set "key" = save_policy.key, "title" = trim(save_policy.title), "owner_id" = save_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_policy.policy_id and x."tenant_id" = save_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."workspace_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."workspace_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
create or replace function "better_supabase"."publish_policy"(policy_id uuid, content jsonb, label text default null)
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
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'POLICY_ARCHIVED';
  end if;
  if publish_policy.content is null or jsonb_typeof(publish_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'policy', v_row."id"::text, publish_policy.content,
    null, coalesce(publish_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."workspace_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."workspace_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_policy"(policy_id uuid)
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
  select * into v_row from "better_supabase"."policies" x where x."id" = archive_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."workspace_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."workspace_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_policy"(uuid) to authenticated, service_role;

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function "better_supabase"."acknowledge_policy"(policy_id uuid)
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
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."workspace_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."workspace_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."acknowledge_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function "better_supabase"."list_policies"(tenant uuid, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_policies.tenant, 'controls.read'), false)) or coalesce(better_supabase.can('tenant', list_policies.tenant, 'controls.acknowledge'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "better_supabase"."memberships" am on am."workspace_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "better_supabase"."memberships" pm where pm."workspace_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."policies" x
    where x."tenant_id" = list_policies.tenant
      and (coalesce(list_policies.include_archived, false) or x."archived_at" is null)
      and (not coalesce(list_policies.pending_only, false) or (
        x."requires_acknowledgement" and x."current_version_id" is not null and x."archived_at" is null and (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = x."id" and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()) is null
      ))
  );
end;
$$;
revoke execute on function "better_supabase"."list_policies"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_policies"(uuid, boolean, boolean) to authenticated, service_role;

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function "better_supabase"."policy_acknowledgements"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."policies"%rowtype;
begin
  select * into v_row from "better_supabase"."policies" x where x."id" = policy_acknowledgements.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)) then
    raise exception 'not allowed to read policy acknowledgements' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
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
      where m."workspace_id" = v_row."tenant_id"
    )
  );
end;
$$;
revoke execute on function "better_supabase"."policy_acknowledgements"(uuid) from public, anon;
grant execute on function "better_supabase"."policy_acknowledgements"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."control_frameworks";
create policy bsb_tenant_scope on "better_supabase"."control_frameworks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."controls";
create policy bsb_tenant_scope on "better_supabase"."controls" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."control_evidence";
create policy bsb_tenant_scope on "better_supabase"."control_evidence" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."evidence_tasks";
create policy bsb_tenant_scope on "better_supabase"."evidence_tasks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policies";
create policy bsb_tenant_scope on "better_supabase"."policies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('controls.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.acknowledge')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."policy_acknowledgements";
create policy bsb_tenant_scope on "better_supabase"."policy_acknowledgements" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('controls.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_126_compliance.sql
-- better-supabase module: compliance
-- @bsb-block-data compliance
-- @bsb-hash sha256:6c929f54d736a4816882343a563bc47aaec6bc49ad4e2a866d6c1e557388069d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
