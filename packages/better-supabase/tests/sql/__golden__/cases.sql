-- ==== alone: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:e21381e172e538f2f3d57a78102a6385fbcd8ef600ce2302a382395b36a5a9b8
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

create table if not exists "better_supabase"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  "pipeline_id" uuid,
  "investigation_form_id" uuid,
  "effectiveness_form_id" uuid,
  "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "requires_revisions" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."case_kinds" enable row level security;
revoke all on "better_supabase"."case_kinds" from public, anon, authenticated;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
drop policy if exists case_kinds_read on "better_supabase"."case_kinds";
create policy case_kinds_read on "better_supabase"."case_kinds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind_id" uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 20000),
  -- One of options.severities and options.sources; the functions check them.
  "severity" text check ("severity" is null or length("severity") between 1 and 41),
  "source" text not null default 'internal' check (length("source") between 1 and 41),
  "reporter_id" uuid,
  "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object'),
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "root_cause_submission_id" uuid,
  "effective" boolean,
  "effectiveness_due_on" date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  "effectiveness_notified_for" date,
  "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000),
  "effectiveness_submission_id" uuid,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text check ("close_note" is null or length("close_note") <= 4000),
  "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "kind_id") references "better_supabase"."case_kinds" ("tenant_id", "id") on delete restrict
);
create index if not exists "cases_status_idx" on "better_supabase"."cases" ("tenant_id", "status");
create index if not exists "cases_kind_stage_idx" on "better_supabase"."cases" ("tenant_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "better_supabase"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "better_supabase"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "better_supabase"."cases" enable row level security;
revoke all on "better_supabase"."cases" from public, anon, authenticated;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
drop policy if exists cases_read on "better_supabase"."cases";
create policy cases_read on "better_supabase"."cases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "case_id" uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  "task_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "required" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("case_id", "task_id"),
  foreign key ("tenant_id", "case_id") references "better_supabase"."cases" ("tenant_id", "id") on delete cascade
);
create index if not exists "case_actions_tenant_parent_idx" on "better_supabase"."case_actions" ("tenant_id", "case_id");
create index if not exists "case_actions_task_idx" on "better_supabase"."case_actions" ("task_id");
alter table "better_supabase"."case_actions" enable row level security;
revoke all on "better_supabase"."case_actions" from public, anon, authenticated;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
drop policy if exists case_actions_read on "better_supabase"."case_actions";
create policy case_actions_read on "better_supabase"."case_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = ensure_case_kinds.tenant) then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "better_supabase"."case_kinds" x
    where x."tenant_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."tenant_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."case_kinds" x
    where x."tenant_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "better_supabase"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_kind."tenant_id"::text || ':case', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."cases" x where x."tenant_id" = v_kind."tenant_id";
  v_identifier := '' || v_seq::text;
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "better_supabase"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "better_supabase"."case_kinds" x
  where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "better_supabase"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "better_supabase"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "better_supabase"."case_kinds";
  v_input jsonb;
  v_row "better_supabase"."cases";
begin
  raise exception 'install the forms block to open cases from submissions' using errcode = '55000', hint = 'CASE_FORMS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_old "better_supabase"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    null;
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      null;
    elsif v_row."status" = 'canceled' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
  v_task uuid;
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "better_supabase"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "better_supabase"."case_actions";
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_action."id";
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "better_supabase"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") from public, anon, authenticated;
grant execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "better_supabase"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "better_supabase"."cases";
create trigger bsb_case_guard before update of "stage_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_case_guard();

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "better_supabase"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_days integer;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if false then
    if v_row."effectiveness_due_on" is null then
      update "better_supabase"."cases" x set "effectiveness_due_on" = current_date + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "better_supabase"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    null;
    
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_kind "better_supabase"."case_kinds";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."tenant_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at") order by x."created_at")
      from "better_supabase"."case_actions" x where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("better_supabase"."case_blockers_of"(v_row)),
    'relations', '{}'::jsonb
  );
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "better_supabase"."cases" x
    where x."tenant_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "better_supabase"."case_kinds" y where y."tenant_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "better_supabase"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "better_supabase"."cases" x
      join "better_supabase"."case_kinds" y on y."id" = x."kind_id"
      where x."tenant_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:2b67ee69a9939f8f5d8ebd3f11c9d8f07b6d018213274a7ac0991fa248103428
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

create table if not exists "better_supabase"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  "pipeline_id" uuid,
  "investigation_form_id" uuid,
  "effectiveness_form_id" uuid,
  "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "requires_revisions" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."case_kinds" enable row level security;
revoke all on "better_supabase"."case_kinds" from public, anon, authenticated;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
drop policy if exists case_kinds_read on "better_supabase"."case_kinds";
create policy case_kinds_read on "better_supabase"."case_kinds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind_id" uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 20000),
  -- One of options.severities and options.sources; the functions check them.
  "severity" text check ("severity" is null or length("severity") between 1 and 41),
  "source" text not null default 'internal' check (length("source") between 1 and 41),
  "reporter_id" uuid,
  "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object'),
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "root_cause_submission_id" uuid,
  "effective" boolean,
  "effectiveness_due_on" date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  "effectiveness_notified_for" date,
  "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000),
  "effectiveness_submission_id" uuid,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text check ("close_note" is null or length("close_note") <= 4000),
  "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "kind_id") references "better_supabase"."case_kinds" ("tenant_id", "id") on delete restrict
);
create index if not exists "cases_status_idx" on "better_supabase"."cases" ("tenant_id", "status");
create index if not exists "cases_kind_stage_idx" on "better_supabase"."cases" ("tenant_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "better_supabase"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "better_supabase"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "better_supabase"."cases" enable row level security;
revoke all on "better_supabase"."cases" from public, anon, authenticated;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
drop policy if exists cases_read on "better_supabase"."cases";
create policy cases_read on "better_supabase"."cases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "case_id" uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  "task_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "required" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("case_id", "task_id"),
  foreign key ("tenant_id", "case_id") references "better_supabase"."cases" ("tenant_id", "id") on delete cascade
);
create index if not exists "case_actions_tenant_parent_idx" on "better_supabase"."case_actions" ("tenant_id", "case_id");
create index if not exists "case_actions_task_idx" on "better_supabase"."case_actions" ("task_id");
alter table "better_supabase"."case_actions" enable row level security;
revoke all on "better_supabase"."case_actions" from public, anon, authenticated;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
drop policy if exists case_actions_read on "better_supabase"."case_actions";
create policy case_actions_read on "better_supabase"."case_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = ensure_case_kinds.tenant) then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "better_supabase"."case_kinds" x
    where x."tenant_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."tenant_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('case_kind.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.created',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'case kind created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix")
  );
  else
    update "better_supabase"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    perform "better_supabase".emit_event('case_kind.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.updated',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'case kind updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('case_kind.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.archived',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'case kind archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."case_kinds" x
    where x."tenant_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "better_supabase"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  v_seq := "better_supabase"."next_number"(v_kind."tenant_id", 'case', now());
  v_identifier := better_supabase.format_assigned_number('{yyyy}-{n:4}', v_seq, now());
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'case', v_row."id"::text, v_input ->> 'originType', v_input ->> 'originId', auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'case' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('case.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.created',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case opened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "better_supabase"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "better_supabase"."case_kinds" x
  where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "better_supabase"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "better_supabase"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "better_supabase"."case_kinds";
  v_input jsonb;
  v_row "better_supabase"."cases";
begin
  select x."tenant_id", x."respondent_id", coalesce(x."answers", '{}'::jsonb)
    into v_tenant, v_respondent, v_answers
  from "better_supabase"."form_submissions" x
  where x."id" = case_from_submission.submission_id;
  if not found then
    raise exception 'no such form submission' using errcode = 'P0002', hint = 'CASE_INVALID';
  end if;
  v_key := coalesce(nullif(v_answers ->> 'kind', ''), 'complaint');
  perform "better_supabase"."ensure_case_kinds"(v_tenant);
  select * into v_kind from "better_supabase"."case_kinds" x
  where x."tenant_id" = v_tenant and x."key" = v_key and x."archived_at" is null;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_input := jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(trim(v_answers ->> 'title'), ''), v_kind."name" || ' from a form'),
    'description', nullif(trim(v_answers ->> 'description'), ''),
    'severity', case when (v_answers ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[]) then v_answers ->> 'severity' end,
    'source', case
      when (v_answers ->> 'source') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[]) then v_answers ->> 'source'
      when v_respondent is null and 'anonymous' = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[]) then 'anonymous'
      when 'customer' = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[]) then 'customer'
      else (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])[1]
    end,
    'occurredAt', v_answers ->> 'occurredAt',
    'reporterContact', nullif(jsonb_strip_nulls(jsonb_build_object(
      'name', nullif(trim(v_answers ->> 'name'), ''),
      'email', nullif(trim(v_answers ->> 'email'), ''),
      'phone', nullif(trim(v_answers ->> 'phone'), '')
    )), '{}'::jsonb)
  ));
  v_row := "better_supabase"."open_case_as"(v_kind."id", v_input, v_respondent);
  return jsonb_build_object('subjectType', 'case', 'subjectId', v_row."id"::text);
end;
$$;
revoke execute on function "better_supabase"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_old "better_supabase"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    perform "better_supabase".emit_event('case.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'changed', to_jsonb(v_changed)), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.updated',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'changed', to_jsonb(v_changed))
  );
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      perform "better_supabase".emit_event('case.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'note', null), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.closed',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'note', null)
  );
    elsif v_row."status" = 'canceled' then
      perform "better_supabase".emit_event('case.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', null), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.cancelled',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', null)
  );
    else
      perform "better_supabase".emit_event('case.reopened', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', null), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.reopened',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case reopened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', null)
  );
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('case.root_cause_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'rootCause', v_row."root_cause"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.root_cause_recorded',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case root cause recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'rootCause', v_row."root_cause")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('case.effectiveness_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'effective', v_row."effective", 'note', v_row."effectiveness_note"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.effectiveness_recorded',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case effectiveness recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'effective', v_row."effective", 'note', v_row."effectiveness_note")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
  v_task uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."cases" x where x."id" = create_case_action.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(create_case_action.type, '') <> all (array['containment', 'correction', 'corrective', 'preventive', 'improvement']::text[]) then
    raise exception 'type is containment, correction, corrective, preventive or improvement' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(trim(create_case_action.title)), 0) = 0 then
    raise exception 'an action needs a title' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_task := ("better_supabase"."create_task"(v_row."tenant_id",
    jsonb_strip_nulls(jsonb_build_object('title', trim(create_case_action.title), 'dueAt', create_case_action.due_at)),
    case when create_case_action.assignee_id is null then '{}'::uuid[] else array[create_case_action.assignee_id] end
  ) ->> 'id')::uuid;
  insert into "better_supabase"."case_actions" ("tenant_id", "case_id", "task_id", "type", "required")
  values (v_row."tenant_id", v_row."id", v_task, create_case_action.type, coalesce(create_case_action.required, true))
  returning * into v_action;
  insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'task', v_task::text, 'case', v_row."id"::text, auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'task' and x."source_id" = v_task::text
    );
  perform "better_supabase".emit_event('case_action.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', v_task, 'type', v_action."type", 'required', v_action."required"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_action.created',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case action added',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', v_task, 'type', v_action."type", 'required', v_action."required")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('actionId', v_action."id", 'taskId', v_task);
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "better_supabase"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."cases" x where x."id" = link_case_action.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(link_case_action.type, '') <> all (array['containment', 'correction', 'corrective', 'preventive', 'improvement']::text[]) then
    raise exception 'type is containment, correction, corrective, preventive or improvement' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."tasks" i
    where i."id" = link_case_action.task_id and i."tenant_id"::text = v_row."tenant_id"::text
  ) then
    raise exception 'no such work item in this organization' using errcode = 'P0002', hint = 'CASE_INVALID';
  end if;
  begin
    insert into "better_supabase"."case_actions" ("tenant_id", "case_id", "task_id", "type", "required")
    values (v_row."tenant_id", v_row."id", link_case_action.task_id, link_case_action.type, coalesce(link_case_action.required, true))
    returning * into v_action;
  exception when unique_violation then
    raise exception 'the work item is already an action of this case' using errcode = '22023', hint = 'CASE_INVALID';
  end;
  perform "better_supabase".emit_event('case_action.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', link_case_action.task_id, 'type', v_action."type", 'required', v_action."required"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_action.created',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case action added',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', link_case_action.task_id, 'type', v_action."type", 'required', v_action."required")
  );
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('actionId', v_action."id", 'taskId', link_case_action.task_id);
end;
$$;
revoke execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "better_supabase"."case_actions";
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_action."id";
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  perform "better_supabase".emit_event('case_action.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', v_action."task_id", 'type', v_action."type"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_action.deleted',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case action removed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'actionId', v_action."id", 'taskId', v_action."task_id", 'type', v_action."type")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "better_supabase"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
  v_policy jsonb;
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_actions" and not exists (
    select 1 from "better_supabase"."case_actions" x where x."case_id" = case_blockers_of.target."id" and x."required"
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_REQUIRED'::text;
  end if;
  if exists (
    select 1 from "better_supabase"."case_actions" x
    join "better_supabase"."tasks" i on i."id" = x."task_id"
    where x."case_id" = case_blockers_of.target."id" and x."required"
      and i."state" not in ('completed', 'canceled')
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_OPEN'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  v_policy := "better_supabase"."approval_effective_policy"(case_blockers_of.target."tenant_id", 'case', 'close',
    jsonb_build_object('caseId', case_blockers_of.target."id", 'kind', v_kind."key", 'severity', case_blockers_of.target."severity"));
  if (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0)
    and not exists (
      select 1 from "better_supabase"."approval_requests" r
      where r."subject_type" = 'case'
        and r."subject_id" = case_blockers_of.target."id"::text
        and r."action" = 'close'
        and r."status" = 'approved'
    ) then
    v_blockers := v_blockers || 'CASE_APPROVAL_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") from public, anon, authenticated;
grant execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "better_supabase"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
      perform "better_supabase"."version_insert"(new."tenant_id", 'case', new."id"::text,
        jsonb_build_object('id', new."id", 'organizationId', new."tenant_id", 'kindId', new."kind_id", 'number', new."number", 'title', new."title", 'description', new."description", 'severity', new."severity", 'source', new."source", 'reporterId', new."reporter_id", 'reporterContact', new."reporter_contact", 'ownerId', new."owner_id", 'occurredAt', new."occurred_at", 'detectedAt', new."detected_at", 'dueOn', new."due_on", 'pipelineId', new."pipeline_id", 'stageId', new."stage_id", 'stageEnteredAt', new."stage_entered_at", 'status', new."status", 'rootCause', new."root_cause", 'rootCauseSubmissionId', new."root_cause_submission_id", 'effective', new."effective", 'effectivenessDueOn', new."effectiveness_due_on", 'effectivenessNote', new."effectiveness_note", 'effectivenessSubmissionId', new."effectiveness_submission_id", 'closedAt', new."closed_at", 'closedBy', new."closed_by", 'closeNote', new."close_note", 'rank', new."rank", 'archivedAt', new."archived_at", 'createdBy', new."created_by", 'createdAt', new."created_at", 'updatedAt', new."updated_at"), null, 'Closed ' || new."number", 'manual', true, auth.uid());
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "better_supabase"."cases";
create trigger bsb_case_guard before update of "stage_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_case_guard();

create or replace function "better_supabase"."case_close_approved"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_approved.case_id for update;
  if not found or v_row."status" <> 'open' or cardinality("better_supabase"."case_blockers_of"(v_row)) > 0 then
    return;
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is not null then
    update "better_supabase"."cases" x set "stage_id" = v_stage where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."case_close_approved"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_close_approved"(uuid) to service_role;

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('case.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'note', v_row."close_note"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.closed',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'note', v_row."close_note")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('case.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_case.reason), '')), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.cancelled',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_case.reason), ''))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('case.reopened', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(reopen_case.reason), '')), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.reopened',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case reopened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(reopen_case.reason), ''))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "better_supabase"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_days integer;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if exists (select 1 from "better_supabase"."case_actions" x where x."case_id" = v_row."id" and x."required")
    and not exists (
      select 1 from "better_supabase"."case_actions" x
      join "better_supabase"."tasks" i on i."id" = x."task_id"
      where x."case_id" = v_row."id" and x."required"
        and i."state" not in ('completed', 'canceled')
    ) then
    if v_row."effectiveness_due_on" is null then
      update "better_supabase"."cases" x set "effectiveness_due_on" = coalesce((
      select max(i."closed_at")::date from "better_supabase"."case_actions" x
      join "better_supabase"."tasks" i on i."id" = x."task_id"
      where x."case_id" = v_row."id" and x."required"
    ), current_date) + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "better_supabase"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    perform "better_supabase".emit_event('case.effectiveness_date_reached', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'effectivenessDueOn', v_row."effectiveness_due_on"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.effectiveness_date_reached',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case effectiveness check due',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'effectivenessDueOn', v_row."effectiveness_due_on")
  );
    if v_row."owner_id" is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'case.effectiveness_date_reached',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'case',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(array[v_row."owner_id"]),
        'key', 'case.effectiveness_date_reached:' || v_row."id"::text || ':' || v_row."effectiveness_due_on"::text,
        'data', jsonb_build_object('caseId', v_row."id", 'effectivenessDueOn', v_row."effectiveness_due_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_kind "better_supabase"."case_kinds";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."tenant_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at",
        'title', i."title", 'state', i."state", 'dueAt', i."due_at",
        'done', i."state" in ('completed', 'canceled'),
        'assignees', coalesce((select jsonb_agg(s."user_id") from "better_supabase"."task_assignees" s where s."work_item_id" = x."task_id"), '[]'::jsonb)
      ) order by x."created_at")
      from "better_supabase"."case_actions" x
      left join "better_supabase"."tasks" i on i."id" = x."task_id"
      where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("better_supabase"."case_blockers_of"(v_row)),
    'relations', coalesce((
      select jsonb_object_agg(k.kind, k.count) from (
        select r."kind" as kind, count(*) as count
        from "better_supabase"."relations" r
        where (r."source_type" = 'case' and r."source_id" = v_row."id"::text)
          or (r."target_type" = 'case' and r."target_id" = v_row."id"::text)
        group by r."kind"
      ) k
    ), '{}'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "better_supabase"."cases" x
    where x."tenant_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "better_supabase"."case_kinds" y where y."tenant_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "better_supabase"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "better_supabase"."cases" x
      join "better_supabase"."case_kinds" y on y."id" = x."kind_id"
      where x."tenant_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:6a3e31de313721acba53ac9dd812c550e9c8b657689c701ea60f3a6323256874
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "app_private"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "app_private"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "app_private"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."cases";
    drop policy if exists bsb_tenant_scope_select on "app_private"."cases";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."cases";
    drop policy if exists bsb_tenant_scope_update on "app_private"."cases";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."case_actions";
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
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

create table if not exists "app_private"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  "pipeline_id" uuid,
  "investigation_form_id" uuid,
  "effectiveness_form_id" uuid,
  "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "requires_revisions" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "app_private"."case_kinds" enable row level security;
revoke all on "app_private"."case_kinds" from public, anon, authenticated;
grant select on "app_private"."case_kinds" to authenticated;
grant all on "app_private"."case_kinds" to service_role;
drop policy if exists case_kinds_read on "app_private"."case_kinds";
create policy case_kinds_read on "app_private"."case_kinds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "app_private"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind_id" uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 20000),
  -- One of options.severities and options.sources; the functions check them.
  "severity" text check ("severity" is null or length("severity") between 1 and 41),
  "source" text not null default 'internal' check (length("source") between 1 and 41),
  "reporter_id" uuid,
  "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object'),
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "root_cause_submission_id" uuid,
  "effective" boolean,
  "effectiveness_due_on" date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  "effectiveness_notified_for" date,
  "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000),
  "effectiveness_submission_id" uuid,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text check ("close_note" is null or length("close_note") <= 4000),
  "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "kind_id") references "app_private"."case_kinds" ("tenant_id", "id") on delete restrict
);
create index if not exists "cases_status_idx" on "app_private"."cases" ("tenant_id", "status");
create index if not exists "cases_kind_stage_idx" on "app_private"."cases" ("tenant_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "app_private"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "app_private"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "app_private"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "app_private"."cases" enable row level security;
revoke all on "app_private"."cases" from public, anon, authenticated;
grant select on "app_private"."cases" to authenticated;
grant all on "app_private"."cases" to service_role;
drop policy if exists cases_read on "app_private"."cases";
create policy cases_read on "app_private"."cases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "app_private"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "case_id" uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  "task_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "required" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("case_id", "task_id"),
  foreign key ("tenant_id", "case_id") references "app_private"."cases" ("tenant_id", "id") on delete cascade
);
create index if not exists "case_actions_tenant_parent_idx" on "app_private"."case_actions" ("tenant_id", "case_id");
create index if not exists "case_actions_task_idx" on "app_private"."case_actions" ("task_id");
alter table "app_private"."case_actions" enable row level security;
revoke all on "app_private"."case_actions" from public, anon, authenticated;
grant select on "app_private"."case_actions" to authenticated;
grant all on "app_private"."case_actions" to service_role;
drop policy if exists case_actions_read on "app_private"."case_actions";
create policy case_actions_read on "app_private"."case_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "app_private"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "app_private"."case_kinds" x where x."tenant_id" = ensure_case_kinds.tenant) then
    insert into "app_private"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "app_private"."case_kinds" x
    where x."tenant_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "app_private"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "app_private"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "app_private"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "app_private"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "app_private"."case_kinds" ("tenant_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "app_private"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."tenant_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "app_private"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "app_private"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "app_private"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "app_private"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "app_private"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_case_kind"(uuid) from public, anon;
grant execute on function "app_private"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "app_private"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "app_private"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "app_private"."case_kinds" x
    where x."tenant_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "app_private"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "app_private"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "app_private"."case_kinds";
  v_row "app_private"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "app_private"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "app_private"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "app_private"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_kind."tenant_id"::text || ':case', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "app_private"."cases" x where x."tenant_id" = v_kind."tenant_id";
  v_identifier := '' || v_seq::text;
  select max(x."rank") into v_last from "app_private"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "app_private"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "app_private"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "app_private"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "app_private"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "app_private"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "app_private"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "app_private"."case_kinds" x
  where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "app_private"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "app_private"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "app_private"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "app_private"."case_kinds";
  v_input jsonb;
  v_row "app_private"."cases";
begin
  raise exception 'install the forms block to open cases from submissions' using errcode = '55000', hint = 'CASE_FORMS_NOT_INSTALLED';
end;
$$;
revoke execute on function "app_private"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "app_private"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_old "app_private"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "app_private"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    null;
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      null;
    elsif v_row."status" = 'canceled' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "app_private"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "app_private"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "app_private"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "app_private"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "app_private"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "app_private"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_action "app_private"."case_actions";
  v_task uuid;
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "app_private"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "app_private"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "app_private"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_action "app_private"."case_actions";
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "app_private"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "app_private"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "app_private"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "app_private"."case_actions";
  v_row "app_private"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "app_private"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "app_private"."case_actions" x where x."id" = v_action."id";
  perform "app_private"."schedule_case_effectiveness"(v_row."id");
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."remove_case_action"(uuid) from public, anon;
grant execute on function "app_private"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "app_private"."case_blockers_of"(target "app_private"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "app_private"."case_kinds";
  v_blockers text[] := '{}';
begin
  select * into v_kind from "app_private"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "app_private"."case_blockers_of"("app_private"."cases") from public, anon, authenticated;
grant execute on function "app_private"."case_blockers_of"("app_private"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "app_private"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
begin
  select * into v_row from "app_private"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "app_private"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "app_private"."case_close_blockers"(uuid) from public, anon;
grant execute on function "app_private"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "app_private"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "app_private"."cases";
create trigger bsb_case_guard before update of "stage_id" on "app_private"."cases"
for each row execute function better_supabase.bsb_case_guard();

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "app_private"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "app_private"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."close_case"(uuid, text) from public, anon;
grant execute on function "app_private"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "app_private"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "app_private"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."cancel_case"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "app_private"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "app_private"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."reopen_case"(uuid, text) from public, anon;
grant execute on function "app_private"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "app_private"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_days integer;
begin
  select * into v_row from "app_private"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "app_private"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if false then
    if v_row."effectiveness_due_on" is null then
      update "app_private"."cases" x set "effectiveness_due_on" = current_date + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "app_private"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "app_private"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "app_private"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "app_private"."schedule_case_effectiveness"(x."id") from "app_private"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "app_private"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "app_private"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    null;
    
    update "app_private"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "app_private"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "app_private"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."cases";
  v_kind "app_private"."case_kinds";
begin
  select * into v_row from "app_private"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "app_private"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."tenant_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at") order by x."created_at")
      from "app_private"."case_actions" x where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("app_private"."case_blockers_of"(v_row)),
    'relations', '{}'::jsonb
  );
end;
$$;
revoke execute on function "app_private"."get_case"(uuid) from public, anon;
grant execute on function "app_private"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "app_private"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "app_private"."cases" x
    where x."tenant_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "app_private"."case_kinds" y where y."tenant_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "app_private"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "app_private"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "app_private"."cases" x
      join "app_private"."case_kinds" y on y."id" = x."kind_id"
      where x."tenant_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "app_private"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "app_private"."case_kinds";
create policy bsb_tenant_scope_select on "app_private"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."case_kinds";
create policy bsb_tenant_scope_insert on "app_private"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."case_kinds";
create policy bsb_tenant_scope_update on "app_private"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."case_kinds";
create policy bsb_tenant_scope_delete on "app_private"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."cases";
drop policy if exists bsb_tenant_scope_select on "app_private"."cases";
create policy bsb_tenant_scope_select on "app_private"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."cases";
create policy bsb_tenant_scope_insert on "app_private"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."cases";
create policy bsb_tenant_scope_update on "app_private"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."cases";
create policy bsb_tenant_scope_delete on "app_private"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."case_actions";
drop policy if exists bsb_tenant_scope_select on "app_private"."case_actions";
create policy bsb_tenant_scope_select on "app_private"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."case_actions";
create policy bsb_tenant_scope_insert on "app_private"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."case_actions";
create policy bsb_tenant_scope_update on "app_private"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."case_actions";
create policy bsb_tenant_scope_delete on "app_private"."case_actions" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:eb9303187c8681e51d7255baa253d0141fa50e3cab87611e46809da39d8dc464
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

create table if not exists "better_supabase"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  "pipeline_id" uuid,
  "investigation_form_id" uuid,
  "effectiveness_form_id" uuid,
  "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "requires_revisions" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."case_kinds" enable row level security;
revoke all on "better_supabase"."case_kinds" from public, anon, authenticated;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
drop policy if exists case_kinds_read on "better_supabase"."case_kinds";
create policy case_kinds_read on "better_supabase"."case_kinds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind_id" uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 20000),
  -- One of options.severities and options.sources; the functions check them.
  "severity" text check ("severity" is null or length("severity") between 1 and 41),
  "source" text not null default 'internal' check (length("source") between 1 and 41),
  "reporter_id" uuid,
  "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object'),
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "root_cause_submission_id" uuid,
  "effective" boolean,
  "effectiveness_due_on" date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  "effectiveness_notified_for" date,
  "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000),
  "effectiveness_submission_id" uuid,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text check ("close_note" is null or length("close_note") <= 4000),
  "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "kind_id") references "better_supabase"."case_kinds" ("tenant_id", "id") on delete restrict
);
create index if not exists "cases_status_idx" on "better_supabase"."cases" ("tenant_id", "status");
create index if not exists "cases_kind_stage_idx" on "better_supabase"."cases" ("tenant_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "better_supabase"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "better_supabase"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "better_supabase"."cases" enable row level security;
revoke all on "better_supabase"."cases" from public, anon, authenticated;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
drop policy if exists cases_read on "better_supabase"."cases";
create policy cases_read on "better_supabase"."cases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "case_id" uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  "task_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "required" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("case_id", "task_id"),
  foreign key ("tenant_id", "case_id") references "better_supabase"."cases" ("tenant_id", "id") on delete cascade
);
create index if not exists "case_actions_tenant_parent_idx" on "better_supabase"."case_actions" ("tenant_id", "case_id");
create index if not exists "case_actions_task_idx" on "better_supabase"."case_actions" ("task_id");
alter table "better_supabase"."case_actions" enable row level security;
revoke all on "better_supabase"."case_actions" from public, anon, authenticated;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
drop policy if exists case_actions_read on "better_supabase"."case_actions";
create policy case_actions_read on "better_supabase"."case_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = ensure_case_kinds.tenant) then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "better_supabase"."case_kinds" x
    where x."tenant_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."tenant_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."case_kinds" x
    where x."tenant_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "better_supabase"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_kind."tenant_id"::text || ':case', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."cases" x where x."tenant_id" = v_kind."tenant_id";
  v_identifier := '' || v_seq::text;
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "better_supabase"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "better_supabase"."case_kinds" x
  where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "better_supabase"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "better_supabase"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "better_supabase"."case_kinds";
  v_input jsonb;
  v_row "better_supabase"."cases";
begin
  raise exception 'install the forms block to open cases from submissions' using errcode = '55000', hint = 'CASE_FORMS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_old "better_supabase"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    null;
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      null;
    elsif v_row."status" = 'canceled' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
  v_task uuid;
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "better_supabase"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "better_supabase"."case_actions";
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_action."id";
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "better_supabase"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") from public, anon, authenticated;
grant execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "better_supabase"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "better_supabase"."cases";
create trigger bsb_case_guard before update of "stage_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_case_guard();

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "better_supabase"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_days integer;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if false then
    if v_row."effectiveness_due_on" is null then
      update "better_supabase"."cases" x set "effectiveness_due_on" = current_date + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "better_supabase"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    null;
    
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_kind "better_supabase"."case_kinds";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."tenant_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at") order by x."created_at")
      from "better_supabase"."case_actions" x where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("better_supabase"."case_blockers_of"(v_row)),
    'relations', '{}'::jsonb
  );
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "better_supabase"."cases" x
    where x."tenant_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "better_supabase"."case_kinds" y where y."tenant_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "better_supabase"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "better_supabase"."cases" x
      join "better_supabase"."case_kinds" y on y."id" = x."kind_id"
      where x."tenant_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.cases.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."ensure_case_kinds"(tenant uuid)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ensure_case_kinds"($1) $$;
revoke execute on function "api"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "api"."ensure_case_kinds"(uuid) to service_role;

create or replace function "api"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_case_kind"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "api"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

create or replace function "api"."archive_case_kind"(kind_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_case_kind"($1) $$;
revoke execute on function "api"."archive_case_kind"(uuid) from public, anon;
grant execute on function "api"."archive_case_kind"(uuid) to authenticated, service_role;

create or replace function "api"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_case_kinds"($1, $2) $$;
revoke execute on function "api"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "api"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_case_as"($1, $2, $3) $$;
revoke execute on function "api"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "api"."open_case_as"(uuid, jsonb, uuid) to service_role;

create or replace function "api"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_case"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "api"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

create or replace function "api"."case_from_submission"(submission_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_from_submission"($1) $$;
revoke execute on function "api"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "api"."case_from_submission"(uuid) to service_role;

create or replace function "api"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_case"($1, $2) $$;
revoke execute on function "api"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_case"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_case_root_cause"($1, $2, $3) $$;
revoke execute on function "api"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "api"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_case_effectiveness"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "api"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

create or replace function "api"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_case_action"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "api"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

create or replace function "api"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_case_action"($1, $2, $3, $4) $$;
revoke execute on function "api"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "api"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."remove_case_action"(action_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_case_action"($1) $$;
revoke execute on function "api"."remove_case_action"(uuid) from public, anon;
grant execute on function "api"."remove_case_action"(uuid) to authenticated, service_role;

create or replace function "api"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_blockers_of"($1) $$;
revoke execute on function "api"."case_blockers_of"(better_supabase.cases) from public, anon, authenticated;
grant execute on function "api"."case_blockers_of"(better_supabase.cases) to service_role;

create or replace function "api"."case_close_blockers"(case_id uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_close_blockers"($1) $$;
revoke execute on function "api"."case_close_blockers"(uuid) from public, anon;
grant execute on function "api"."case_close_blockers"(uuid) to authenticated, service_role;

create or replace function "api"."close_case"(case_id uuid, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_case"($1, $2) $$;
revoke execute on function "api"."close_case"(uuid, text) from public, anon;
grant execute on function "api"."close_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_case"($1, $2) $$;
revoke execute on function "api"."cancel_case"(uuid, text) from public, anon;
grant execute on function "api"."cancel_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reopen_case"($1, $2) $$;
revoke execute on function "api"."reopen_case"(uuid, text) from public, anon;
grant execute on function "api"."reopen_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."schedule_case_effectiveness"(case_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_case_effectiveness"($1) $$;
revoke execute on function "api"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "api"."schedule_case_effectiveness"(uuid) to service_role;

create or replace function "api"."notify_due_case_effectiveness"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_case_effectiveness"() $$;
revoke execute on function "api"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "api"."notify_due_case_effectiveness"() to service_role;

create or replace function "api"."get_case"(case_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_case"($1) $$;
revoke execute on function "api"."get_case"(uuid) from public, anon;
grant execute on function "api"."get_case"(uuid) to authenticated, service_role;

create or replace function "api"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_cases"($1, $2) $$;
revoke execute on function "api"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_cases"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_stats"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "api"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:1795c0fba3465a6769f6c89eb59050b971daaa52cadcd96b0a83e666be6d66d3
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

-- better_supabase.case_kinds is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."case_kinds" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."case_kinds" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."case_kinds" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_]{0,40}$');
alter table "better_supabase"."case_kinds" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."case_kinds" add column if not exists "prefix" text check ("prefix" ~ '^[A-Z]{1,6}$');
alter table "better_supabase"."case_kinds" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."case_kinds" add column if not exists "investigation_form_id" uuid;
alter table "better_supabase"."case_kinds" add column if not exists "effectiveness_form_id" uuid;
alter table "better_supabase"."case_kinds" add column if not exists "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365);
alter table "better_supabase"."case_kinds" add column if not exists "requires_root_cause" boolean not null default true;
alter table "better_supabase"."case_kinds" add column if not exists "requires_actions" boolean not null default true;
alter table "better_supabase"."case_kinds" add column if not exists "requires_effectiveness" boolean not null default false;
alter table "better_supabase"."case_kinds" add column if not exists "requires_revisions" boolean not null default false;
alter table "better_supabase"."case_kinds" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."case_kinds" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."case_kinds" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_case_kinds_tenant_key_key" on "better_supabase"."case_kinds" ("tenant_id", "key");
create unique index if not exists "bsb_case_kinds_tenant_id_key" on "better_supabase"."case_kinds" ("tenant_id", "id");
alter table "better_supabase"."case_kinds" enable row level security;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
drop policy if exists bsb_case_kinds_read on "better_supabase"."case_kinds";
create policy bsb_case_kinds_read on "better_supabase"."case_kinds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

-- better_supabase.cases is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."cases" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."cases" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."cases" add column if not exists "kind_id" uuid;
alter table "better_supabase"."cases" add column if not exists "number" text check (length("number") between 1 and 100);
alter table "better_supabase"."cases" add column if not exists "sequence" bigint;
alter table "better_supabase"."cases" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."cases" add column if not exists "description" text check ("description" is null or length("description") <= 20000);
alter table "better_supabase"."cases" add column if not exists "severity" text check ("severity" is null or length("severity") between 1 and 41);
alter table "better_supabase"."cases" add column if not exists "source" text not null default 'internal' check (length("source") between 1 and 41);
alter table "better_supabase"."cases" add column if not exists "reporter_id" uuid;
alter table "better_supabase"."cases" add column if not exists "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object');
alter table "better_supabase"."cases" add column if not exists "owner_id" uuid;
alter table "better_supabase"."cases" add column if not exists "occurred_at" timestamptz;
alter table "better_supabase"."cases" add column if not exists "detected_at" timestamptz not null default now();
alter table "better_supabase"."cases" add column if not exists "due_on" date;
alter table "better_supabase"."cases" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."cases" add column if not exists "stage_id" uuid;
alter table "better_supabase"."cases" add column if not exists "stage_entered_at" timestamptz;
alter table "better_supabase"."cases" add column if not exists "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled'));
alter table "better_supabase"."cases" add column if not exists "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000);
alter table "better_supabase"."cases" add column if not exists "root_cause_submission_id" uuid;
alter table "better_supabase"."cases" add column if not exists "effective" boolean;
alter table "better_supabase"."cases" add column if not exists "effectiveness_due_on" date;
alter table "better_supabase"."cases" add column if not exists "effectiveness_notified_for" date;
alter table "better_supabase"."cases" add column if not exists "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000);
alter table "better_supabase"."cases" add column if not exists "effectiveness_submission_id" uuid;
alter table "better_supabase"."cases" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."cases" add column if not exists "closed_by" uuid;
alter table "better_supabase"."cases" add column if not exists "close_note" text check ("close_note" is null or length("close_note") <= 4000);
alter table "better_supabase"."cases" add column if not exists "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$');
alter table "better_supabase"."cases" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."cases" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."cases" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."cases" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_cases_tenant_number_key" on "better_supabase"."cases" ("tenant_id", "number");
create unique index if not exists "bsb_cases_tenant_id_key" on "better_supabase"."cases" ("tenant_id", "id");
create index if not exists "cases_status_idx" on "better_supabase"."cases" ("tenant_id", "status");
create index if not exists "cases_kind_stage_idx" on "better_supabase"."cases" ("tenant_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "better_supabase"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "better_supabase"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "better_supabase"."cases" enable row level security;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
drop policy if exists bsb_cases_read on "better_supabase"."cases";
create policy bsb_cases_read on "better_supabase"."cases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

-- better_supabase.case_actions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."case_actions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."case_actions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."case_actions" add column if not exists "case_id" uuid;
alter table "better_supabase"."case_actions" add column if not exists "task_id" uuid;
alter table "better_supabase"."case_actions" add column if not exists "type" text check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement'));
alter table "better_supabase"."case_actions" add column if not exists "required" boolean not null default true;
alter table "better_supabase"."case_actions" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_case_actions_case_task_key" on "better_supabase"."case_actions" ("case_id", "task_id");
create index if not exists "case_actions_tenant_parent_idx" on "better_supabase"."case_actions" ("tenant_id", "case_id");
create index if not exists "case_actions_task_idx" on "better_supabase"."case_actions" ("task_id");
alter table "better_supabase"."case_actions" enable row level security;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
drop policy if exists bsb_case_actions_read on "better_supabase"."case_actions";
create policy bsb_case_actions_read on "better_supabase"."case_actions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = ensure_case_kinds.tenant) then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "better_supabase"."case_kinds" x
    where x."tenant_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."tenant_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."case_kinds" x
    where x."tenant_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "better_supabase"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_kind."tenant_id"::text || ':case', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."cases" x where x."tenant_id" = v_kind."tenant_id";
  v_identifier := '' || v_seq::text;
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "better_supabase"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "better_supabase"."case_kinds" x
  where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "better_supabase"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "better_supabase"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "better_supabase"."case_kinds";
  v_input jsonb;
  v_row "better_supabase"."cases";
begin
  raise exception 'install the forms block to open cases from submissions' using errcode = '55000', hint = 'CASE_FORMS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_old "better_supabase"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    null;
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      null;
    elsif v_row."status" = 'canceled' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
  v_task uuid;
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "better_supabase"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "better_supabase"."case_actions";
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_action."id";
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "better_supabase"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") from public, anon, authenticated;
grant execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "better_supabase"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "better_supabase"."cases";
create trigger bsb_case_guard before update of "stage_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_case_guard();

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "better_supabase"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_days integer;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if false then
    if v_row."effectiveness_due_on" is null then
      update "better_supabase"."cases" x set "effectiveness_due_on" = current_date + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "better_supabase"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    null;
    
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_kind "better_supabase"."case_kinds";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."tenant_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at") order by x."created_at")
      from "better_supabase"."case_actions" x where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("better_supabase"."case_blockers_of"(v_row)),
    'relations', '{}'::jsonb
  );
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "better_supabase"."cases" x
    where x."tenant_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "better_supabase"."case_kinds" y where y."tenant_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "better_supabase"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "better_supabase"."cases" x
      join "better_supabase"."case_kinds" y on y."id" = x."kind_id"
      where x."tenant_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:dc51a6891862d44124aa19feb7e8ac3b09cf6630741315ce36839920f61172bd
-- Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.

create table if not exists "better_supabase"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  "pipeline_id" uuid,
  "investigation_form_id" uuid,
  "effectiveness_form_id" uuid,
  "effectiveness_after_days" integer check ("effectiveness_after_days" is null or "effectiveness_after_days" between 1 and 365),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "requires_revisions" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  unique ("org_id", "id")
);
alter table "better_supabase"."case_kinds" enable row level security;
revoke all on "better_supabase"."case_kinds" from public, anon, authenticated;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
drop policy if exists case_kinds_read on "better_supabase"."case_kinds";
create policy case_kinds_read on "better_supabase"."case_kinds"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "kind_id" uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 20000),
  -- One of options.severities and options.sources; the functions check them.
  "severity" text check ("severity" is null or length("severity") between 1 and 41),
  "source" text not null default 'internal' check (length("source") between 1 and 41),
  "reporter_id" uuid,
  "reporter_contact" jsonb check ("reporter_contact" is null or jsonb_typeof("reporter_contact") = 'object'),
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "root_cause_submission_id" uuid,
  "effective" boolean,
  "effectiveness_due_on" date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  "effectiveness_notified_for" date,
  "effectiveness_note" text check ("effectiveness_note" is null or length("effectiveness_note") <= 4000),
  "effectiveness_submission_id" uuid,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text check ("close_note" is null or length("close_note") <= 4000),
  "rank" text collate "C" check ("rank" is null or "rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "number"),
  unique ("org_id", "id"),
  foreign key ("org_id", "kind_id") references "better_supabase"."case_kinds" ("org_id", "id") on delete restrict
);
create index if not exists "cases_status_idx" on "better_supabase"."cases" ("org_id", "status");
create index if not exists "cases_kind_stage_idx" on "better_supabase"."cases" ("org_id", "kind_id", "stage_id");
create index if not exists "cases_board_idx" on "better_supabase"."cases" ("pipeline_id", "stage_id", "rank");
create index if not exists "cases_owner_idx" on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
create index if not exists "cases_effectiveness_idx" on "better_supabase"."cases" ("effectiveness_due_on") where "effective" is null and "status" = 'open';
alter table "better_supabase"."cases" enable row level security;
revoke all on "better_supabase"."cases" from public, anon, authenticated;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
drop policy if exists cases_read on "better_supabase"."cases";
create policy cases_read on "better_supabase"."cases"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "case_id" uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  "task_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "required" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("case_id", "task_id"),
  foreign key ("org_id", "case_id") references "better_supabase"."cases" ("org_id", "id") on delete cascade
);
create index if not exists "case_actions_tenant_parent_idx" on "better_supabase"."case_actions" ("org_id", "case_id");
create index if not exists "case_actions_task_idx" on "better_supabase"."case_actions" ("task_id");
alter table "better_supabase"."case_actions" enable row level security;
revoke all on "better_supabase"."case_actions" from public, anon, authenticated;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
drop policy if exists case_actions_read on "better_supabase"."case_actions";
create policy case_actions_read on "better_supabase"."case_actions"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('cases.read')));


-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_case_kinds"(tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from "better_supabase"."case_kinds" x where x."org_id" = ensure_case_kinds.tenant) then
    insert into "better_supabase"."case_kinds" ("org_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ('nonconformity', 'Nonconformity', 'NC', null::integer, true, true, false, false),
      ('complaint', 'Complaint', 'CMP', null::integer, true, true, false, false),
      ('incident', 'Incident', 'INC', null::integer, true, true, false, false),
      ('near_miss', 'Near miss', 'NM', null::integer, true, false, false, false),
      ('observation', 'Observation', 'OBS', null::integer, false, false, false, false),
      ('improvement', 'Improvement', 'IMP', null::integer, false, true, false, false),
      ('change', 'Change request', 'CHG', null::integer, false, true, false, true),
      ('finding', 'Audit finding', 'FND', null::integer, true, true, false, false)
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x."id" as id from "better_supabase"."case_kinds" x
    where x."org_id" = ensure_case_kinds.tenant and x."pipeline_id" is null
    for update skip locked
  loop
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(ensure_case_kinds.tenant, 'case', v_kind.id::text)
    where x."id" = v_kind.id;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."ensure_case_kinds"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_case_kinds"(uuid) to service_role;

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_case_kind.tenant is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'key must be lowercase letters, digits and underscores' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    raise exception 'prefix must be 1 to 6 capital letters' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    raise exception 'effectiveness_after_days is a whole number from 1 to 365' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("org_id", "key", "name", "prefix", "investigation_form_id", "effectiveness_form_id", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update "better_supabase"."case_kinds" x set "pipeline_id" = "better_supabase"."default_pipeline"(v_row."org_id", 'case', v_row."id"::text)
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."case_kinds" x set
      "key" = save_case_kind.key,
      "name" = trim(save_case_kind.name),
      "prefix" = save_case_kind.prefix,
      "investigation_form_id" = save_case_kind.investigation_form_id,
      "effectiveness_form_id" = save_case_kind.effectiveness_form_id,
      "effectiveness_after_days" = save_case_kind.effectiveness_after_days,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "requires_revisions" = coalesce(save_case_kind.requires_revisions, false),
      "updated_at" = now()
    where x."id" = save_case_kind.kind_id and x."org_id" = save_case_kind.tenant
    returning * into v_row;
    if not found then
      raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another kind of this organization has this key' using errcode = '22023', hint = 'CASE_KIND_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid) to authenticated, service_role;

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_case_kinds.tenant is not null and coalesce(better_supabase.can('tenant', list_case_kinds.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_case_kinds"(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'pipelineId', x."pipeline_id", 'investigationFormId', x."investigation_form_id", 'effectivenessFormId', x."effectiveness_form_id", 'effectivenessAfterDays', x."effectiveness_after_days", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'requiresRevisions', x."requires_revisions", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."case_kinds" x
    where x."org_id" = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function "better_supabase"."open_case_as"(kind_id uuid, input jsonb, reporter uuid default null)
returns "better_supabase"."cases"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."org_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."org_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_kind."org_id"::text || ':case', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."cases" x where x."org_id" = v_kind."org_id";
  v_identifier := '' || v_seq::text;
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."org_id" = v_kind."org_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("org_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."org_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."open_case_as"(uuid, jsonb, uuid) to service_role;

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row "better_supabase"."cases";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_case.tenant is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false))) then
    raise exception 'not allowed to open cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  perform "better_supabase"."ensure_case_kinds"(open_case.tenant);
  select x."id" into v_kind from "better_supabase"."case_kinds" x
  where x."org_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  v_row := "better_supabase"."open_case_as"(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date, jsonb) to authenticated, service_role;

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function "better_supabase"."case_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind "better_supabase"."case_kinds";
  v_input jsonb;
  v_row "better_supabase"."cases";
begin
  raise exception 'install the forms block to open cases from submissions' using errcode = '55000', hint = 'CASE_FORMS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."case_from_submission"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."case_from_submission"(uuid) to service_role;

-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_old "better_supabase"."cases";
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  v_old := v_row;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in ('title', 'description', 'severity', 'source', 'ownerId', 'occurredAt', 'dueOn', 'reporterContact', 'fields', 'stageId', 'rank')) then
    raise exception 'changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row."stage_id" end;
  if v_stage is null then
    raise exception 'stageId can''t be null' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_row."status" <> 'open' and (v_stage is not distinct from v_row."stage_id" or v_edited) then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if v_stage is distinct from v_row."stage_id" then
    v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = v_stage);
    if (coalesce(v_outcome, 'open') <> 'open' or v_row."status" <> 'open') and not (
      case when v_outcome = 'success' and v_row."status" = 'open' then ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) else (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.close'), false))) end
    ) then
      raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(update_case.changes ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'reporterContact' and jsonb_typeof(update_case.changes -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if update_case.changes ? 'severity' and update_case.changes ->> 'severity' is not null and not ((update_case.changes ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if update_case.changes ? 'source' and not (coalesce(update_case.changes ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if update_case.changes ? 'fields' and jsonb_typeof(update_case.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "title" = v_title,
    "description" = case when update_case.changes ? 'description' then nullif(trim(update_case.changes ->> 'description'), '') else x."description" end,
    "reporter_contact" = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x."reporter_contact" end,
    "severity" = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x."severity" end,
    "source" = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x."source" end,
    "owner_id" = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "occurred_at" = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x."occurred_at" end,
    "due_on" = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x."due_on" end,
    "rank" = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x."rank" end,
    "stage_id" = v_stage,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_edited then
    null;
  end if;
  if v_row."status" is distinct from v_old."status" then
    if v_row."status" = 'closed' then
      null;
    elsif v_row."status" = 'canceled' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

-- Records the root cause, from text or an investigation form submission.
create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    raise exception 'a root cause is 1 to 10000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "root_cause" = trim(record_case_root_cause.root_cause),
    "root_cause_submission_id" = coalesce(record_case_root_cause.submission_id, x."root_cause_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text, uuid) to authenticated, service_role;

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if record_case_effectiveness.effective is null then
    raise exception 'effective is true or false' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  update "better_supabase"."cases" x set
    "effective" = record_case_effectiveness.effective,
    "effectiveness_note" = nullif(trim(record_case_effectiveness.note), ''),
    "effectiveness_submission_id" = coalesce(record_case_effectiveness.submission_id, x."effectiveness_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, uuid, text) to authenticated, service_role;

-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
  v_task uuid;
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

-- Makes an existing work item an action of the case.
create or replace function "better_supabase"."link_case_action"(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_action "better_supabase"."case_actions";
begin
  raise exception 'install the tasks block to give cases actions' using errcode = '55000', hint = 'CASE_TASKS_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."link_case_action"(uuid, uuid, text, boolean) to authenticated, service_role;

-- Removes an action from its case; the work item stays.
create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action "better_supabase"."case_actions";
  v_row "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'no such case action' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = v_action."case_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.write'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) then
    raise exception 'not allowed to change this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_action."id";
  perform "better_supabase"."schedule_case_effectiveness"(v_row."id");
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;


-- What still stops the case in row from closing, as hint codes in check order.
create or replace function "better_supabase"."case_blockers_of"(target "better_supabase"."cases")
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") from public, anon, authenticated;
grant execute on function "better_supabase"."case_blockers_of"("better_supabase"."cases") to service_role;

-- What still stops the case from closing: CASE_ROOT_CAUSE_REQUIRED,
-- CASE_ACTIONS_REQUIRED, CASE_ACTIONS_OPEN, CASE_EFFECTIVENESS_REQUIRED and
-- CASE_DOCUMENTS_NOT_REVISED, as the kind requires them, and
-- CASE_APPROVAL_REQUIRED while approvals asks for a decision on closing. Empty
-- when it may close.
create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  return "better_supabase"."case_blockers_of"(v_row);
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

-- Keeps status on the stage's outcome: a move to a success stage closes the
-- case once nothing blocks it, a failure stage cancels it and an open stage
-- reopens it. Runs before the pipelines trigger (triggers fire by name).
create or replace function better_supabase.bsb_case_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_case_guard() from public, anon, authenticated;
drop trigger if exists bsb_case_guard on "better_supabase"."cases";
create trigger bsb_case_guard before update of "stage_id" on "better_supabase"."cases"
for each row execute function better_supabase.bsb_case_guard();

-- Closes the case: moves it to its pipeline's first success stage. Refuses
-- with the first blocker as the hint and every blocker in the detail while one
-- remains.
create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.close'), false))) or (coalesce(v_row."owner_id" = (select auth.uid()), false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))))) then
    raise exception 'not allowed to close this case' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(close_case.note) > 4000 then
    raise exception 'note is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active success stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(close_case.note), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

-- Cancels the case: moves it to its pipeline's first failure stage.
create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is closed or canceled' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if length(cancel_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'failure' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active failure stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage, "close_note" = nullif(trim(cancel_case.reason), '')
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

-- Reopens a closed or canceled case on its pipeline's first open stage.
create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.close'), false))) then
    raise exception 'not allowed to close, cancel or reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    raise exception 'the case is open' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(reopen_case.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is null then
    raise exception 'the case''s pipeline has no active open stage' using errcode = '55000', hint = 'CASE_STAGE_MISSING';
  end if;
  update "better_supabase"."cases" x set "stage_id" = v_stage
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

-- Sets when the effectiveness check is due: the kind's days after the last
-- required action was done. Runs when actions change and before each
-- notify_due_case_effectiveness run.
create or replace function "better_supabase"."schedule_case_effectiveness"(case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_days integer;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = schedule_case_effectiveness.case_id for update;
  if not found or v_row."status" <> 'open' or v_row."effective" is not null then
    return;
  end if;
  select y."effectiveness_after_days" into v_days from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id";
  if v_days is null then
    return;
  end if;
  if false then
    if v_row."effectiveness_due_on" is null then
      update "better_supabase"."cases" x set "effectiveness_due_on" = current_date + v_days, "updated_at" = now()
      where x."id" = v_row."id";
    end if;
  elsif v_row."effectiveness_due_on" is not null then
    update "better_supabase"."cases" x set "effectiveness_due_on" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
end;
$$;
revoke execute on function "better_supabase"."schedule_case_effectiveness"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_case_effectiveness"(uuid) to service_role;
-- Schedules the checks whose required actions are now done, then reports each
-- open case whose effectiveness check has come due, once per date: a
-- case.effectiveness_date_reached event and, with notifications, a
-- notification to its owner. Run it daily (the effectiveness-due schedule).
create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    null;
    
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to service_role;


-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_kind "better_supabase"."case_kinds";
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'no such case' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_row."kind_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'reporterContact', v_row."reporter_contact", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'pipelineId', v_row."pipeline_id", 'stageId', v_row."stage_id", 'stageEnteredAt', v_row."stage_entered_at", 'status', v_row."status", 'rootCause', v_row."root_cause", 'rootCauseSubmissionId', v_row."root_cause_submission_id", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'effectivenessNote', v_row."effectiveness_note", 'effectivenessSubmissionId', v_row."effectiveness_submission_id", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'rank', v_row."rank", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'kind', jsonb_build_object('id', v_kind."id", 'organizationId', v_kind."org_id", 'key', v_kind."key", 'name', v_kind."name", 'prefix', v_kind."prefix", 'pipelineId', v_kind."pipeline_id", 'investigationFormId', v_kind."investigation_form_id", 'effectivenessFormId', v_kind."effectiveness_form_id", 'effectivenessAfterDays', v_kind."effectiveness_after_days", 'requiresRootCause', v_kind."requires_root_cause", 'requiresActions', v_kind."requires_actions", 'requiresEffectiveness', v_kind."requires_effectiveness", 'requiresRevisions', v_kind."requires_revisions", 'archivedAt', v_kind."archived_at", 'createdAt', v_kind."created_at", 'updatedAt', v_kind."updated_at"),
    'stage', (select jsonb_build_object('id', s."id", 'key', s."key", 'name', s."name", 'outcome', s."outcome")
      from "better_supabase"."pipeline_stages" s where s."id" = v_row."stage_id"),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'taskId', x."task_id", 'type', x."type", 'required', x."required", 'createdAt', x."created_at") order by x."created_at")
      from "better_supabase"."case_actions" x where x."case_id" = v_row."id"
    ), '[]'::jsonb),
    'blockers', to_jsonb("better_supabase"."case_blockers_of"(v_row)),
    'relations', '{}'::jsonb
  );
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_cases.tenant is not null and coalesce(better_supabase.can('tenant', list_cases.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      raise exception 'cursor is not a nextCursor of list_cases' using errcode = '22023', hint = 'CASE_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'reporterContact', x."reporter_contact", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'pipelineId', x."pipeline_id", 'stageId', x."stage_id", 'stageEnteredAt', x."stage_entered_at", 'status', x."status", 'rootCause', x."root_cause", 'rootCauseSubmissionId', x."root_cause_submission_id", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'effectivenessNote', x."effectiveness_note", 'effectivenessSubmissionId', x."effectiveness_submission_id", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'rank', x."rank", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from "better_supabase"."cases" x
    where x."org_id" = list_cases.tenant
      and x."archived_at" is null
      and (not v_filters ? 'kind' or x."kind_id" = (select y."id" from "better_supabase"."case_kinds" y where y."org_id" = list_cases.tenant and y."key" = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x."severity" = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x."source" = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x."owner_id" = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x."stage_id" = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x."status" = 'open' and x."due_on" < current_date))
      and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."root_cause" ilike v_search)
      and (v_after_at is null or (x."created_at", x."id") < (v_after_at, v_after_id))
    order by x."created_at" desc, x."id" desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function "better_supabase"."case_stats"(tenant uuid, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case_stats.tenant is not null and coalesce(better_supabase.can('tenant', case_stats.tenant, 'cases.read'), false))) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if coalesce(case_stats.group_by, '') not in ('severity', 'source', 'stage', 'kind', 'root_cause') then
    raise exception 'group_by is severity, source, stage, kind or root_cause' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x."severity"
          when 'source' then x."source"
          when 'stage' then (select s."key" from "better_supabase"."pipeline_stages" s where s."id" = x."stage_id")
          when 'kind' then y."key"
          else nullif(lower(trim(x."root_cause")), '')
        end as key,
        count(*) as count
      from "better_supabase"."cases" x
      join "better_supabase"."case_kinds" y on y."id" = x."kind_id"
      where x."org_id" = case_stats.tenant
        and x."archived_at" is null
        and (case_stats.kind is null or y."key" = case_stats.kind)
        and (case_stats.since is null or x."created_at" >= case_stats.since)
        and (case_stats.until is null or x."created_at" < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, text, date, date, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_091_cases.sql
-- better-supabase module: cases
-- @bsb-block-data cases
-- @bsb-hash sha256:7afd439d1b21eec44b1f4de82df17f086b4ae6d4cad1aa229d975cec46001b05
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
