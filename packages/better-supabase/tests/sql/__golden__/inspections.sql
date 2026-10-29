-- ==== alone: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:d201ad4a9667fee9d51254d366693bfe97f575d1c6130ab5cdc8455523dc77b9
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null check ("period_end" >= "period_start"),
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
create policy inspection_programs_read on better_supabase.inspection_programs
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  "number" text not null,
  "kind" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "scope" text,
  "criteria" text,
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  "summary" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("program_id") references "better_supabase"."inspection_programs" ("id") on delete set null
);
create index if not exists inspections_status_idx on "better_supabase"."inspections" ("tenant_id", "status");
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;
create policy inspections_read on better_supabase.inspections
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  "number" integer not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "clause" text,
  "case_id" uuid,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("inspection_id") references "better_supabase"."inspections" ("id") on delete cascade
);
create index if not exists inspection_findings_parent_idx on "better_supabase"."inspection_findings" ("inspection_id");
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
create policy inspection_findings_read on better_supabase.inspection_findings
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "better_supabase"."inspection_programs" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "better_supabase"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "better_supabase"."inspections"%rowtype;
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."tenant_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "better_supabase"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "better_supabase"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "better_supabase"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  raise exception 'install the cases block' using errcode = '55000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
  update "better_supabase"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  null;
  return v_case;
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "better_supabase"."inspections" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "better_supabase"."notify_due_inspections"() from public, anon;
grant execute on function "better_supabase"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
create policy bsb_tenant_scope_select on "better_supabase"."inspections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
create policy bsb_tenant_scope_insert on "better_supabase"."inspections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
create policy bsb_tenant_scope_update on "better_supabase"."inspections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
create policy bsb_tenant_scope_delete on "better_supabase"."inspections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_findings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_findings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_findings" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:065b75ae7ab7e0cdad2f7b94d8a64e9b1426444f6648d845b5e8f240b58c79bd
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null check ("period_end" >= "period_start"),
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
create policy inspection_programs_read on better_supabase.inspection_programs
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  "number" text not null,
  "kind" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "scope" text,
  "criteria" text,
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  "summary" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("program_id") references "better_supabase"."inspection_programs" ("id") on delete set null
);
create index if not exists inspections_status_idx on "better_supabase"."inspections" ("tenant_id", "status");
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;
create policy inspections_read on better_supabase.inspections
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  "number" integer not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "clause" text,
  "case_id" uuid,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("inspection_id") references "better_supabase"."inspections" ("id") on delete cascade
);
create index if not exists inspection_findings_parent_idx on "better_supabase"."inspection_findings" ("inspection_id");
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
create policy inspection_findings_read on better_supabase.inspection_findings
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    perform "better_supabase".emit_event('inspection_program.created', jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.created',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    summary => 'saved inspection program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('inspection_program.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.updated',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    summary => 'saved inspection program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection_program.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.approved',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    summary => 'approved inspection program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection_program.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.closed',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    summary => 'closed inspection program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'programId', v_row."id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "better_supabase"."inspection_programs" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.scheduled',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'scheduled inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "better_supabase"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number", 'changed', to_jsonb(v_changed)), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.updated',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'changed inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number", 'changed', to_jsonb(v_changed))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection.started', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.started',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'started inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "better_supabase"."inspections"%rowtype;
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."tenant_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "better_supabase"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  perform "better_supabase".emit_event('inspection_finding.created', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id", 'type', v_row."type"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.created',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    summary => 'added inspection finding',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id", 'type', v_row."type")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "better_supabase"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection_finding.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.updated',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    summary => 'changed inspection finding',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('inspection_finding.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.deleted',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    summary => 'deleted inspection finding',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'findingId', v_row."id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "better_supabase"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  v_case := "better_supabase"."open_case"(v_finding."tenant_id", raise_inspection_finding_case.kind, v_finding."title", v_finding."description", null, 'inspection');
  update "better_supabase"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  perform "better_supabase".emit_event('inspection_finding.case_raised', jsonb_build_object('organizationId', v_finding."tenant_id", 'inspectionId', v_finding."inspection_id", 'findingId', v_finding."id", 'caseId', v_finding."case_id"), 'inspection-findings/' || v_finding."id"::text, (v_finding."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.case_raised',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_finding."id"::text,
    summary => 'raised a case from a finding',
    tenant => (v_finding."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_finding."tenant_id", 'inspectionId', v_finding."inspection_id", 'findingId', v_finding."id", 'caseId', v_finding."case_id")
  );
  return v_case;
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.completed',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'completed inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.closed',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'closed inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('inspection.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.cancelled',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    summary => 'cancelled inspection ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'inspectionId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "better_supabase"."inspections" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "better_supabase"."notify_due_inspections"() from public, anon;
grant execute on function "better_supabase"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
create policy bsb_tenant_scope_select on "better_supabase"."inspections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
create policy bsb_tenant_scope_insert on "better_supabase"."inspections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
create policy bsb_tenant_scope_update on "better_supabase"."inspections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
create policy bsb_tenant_scope_delete on "better_supabase"."inspections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_findings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_findings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_findings" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:d31dc26de4c0977ef9dc3fd794271044b9bfad62fa2b5aa779a7a137e7bdf49f
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "app_private"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."inspections";
    drop policy if exists bsb_tenant_scope_select on "app_private"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."inspections";
    drop policy if exists bsb_tenant_scope_update on "app_private"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_findings";
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
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

create table if not exists "app_private"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null check ("period_end" >= "period_start"),
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "app_private"."inspection_programs" enable row level security;
revoke all on "app_private"."inspection_programs" from public, anon, authenticated;
grant select on "app_private"."inspection_programs" to authenticated;
grant all on "app_private"."inspection_programs" to service_role;
create policy inspection_programs_read on app_private.inspection_programs
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "app_private"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  "number" text not null,
  "kind" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "scope" text,
  "criteria" text,
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  "summary" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("program_id") references "app_private"."inspection_programs" ("id") on delete set null
);
create index if not exists inspections_status_idx on "app_private"."inspections" ("tenant_id", "status");
alter table "app_private"."inspections" enable row level security;
revoke all on "app_private"."inspections" from public, anon, authenticated;
grant select on "app_private"."inspections" to authenticated;
grant all on "app_private"."inspections" to service_role;
create policy inspections_read on app_private.inspections
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "app_private"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  "number" integer not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "clause" text,
  "case_id" uuid,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("inspection_id") references "app_private"."inspections" ("id") on delete cascade
);
create index if not exists inspection_findings_parent_idx on "app_private"."inspection_findings" ("inspection_id");
alter table "app_private"."inspection_findings" enable row level security;
revoke all on "app_private"."inspection_findings" from public, anon, authenticated;
grant select on "app_private"."inspection_findings" to authenticated;
grant all on "app_private"."inspection_findings" to service_role;
create policy inspection_findings_read on app_private.inspection_findings
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "app_private"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "app_private"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "app_private"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "app_private"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "app_private"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "app_private"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "app_private"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "app_private"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "app_private"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "app_private"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "app_private"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "app_private"."close_inspection_program"(uuid) from public, anon;
grant execute on function "app_private"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "app_private"."inspection_programs" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "app_private"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "app_private"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "app_private"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "app_private"."inspections" ("tenant_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "app_private"."inspections" x where x."tenant_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "app_private"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "app_private"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."start_inspection"(uuid) from public, anon;
grant execute on function "app_private"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "app_private"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "app_private"."inspections"%rowtype;
  v_row "app_private"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "app_private"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "app_private"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."tenant_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "app_private"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "app_private"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "app_private"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "app_private"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "app_private"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "app_private"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "app_private"."inspection_findings" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "app_private"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "app_private"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "app_private"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "app_private"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  raise exception 'install the cases block' using errcode = '55000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
  update "app_private"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  null;
  return v_case;
end;
$$;
revoke execute on function "app_private"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "app_private"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "app_private"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "app_private"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "app_private"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "app_private"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "app_private"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."close_inspection"(uuid) from public, anon;
grant execute on function "app_private"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "app_private"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "app_private"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "app_private"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "app_private"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "app_private"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "app_private"."get_inspection"(uuid) from public, anon;
grant execute on function "app_private"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "app_private"."inspections" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "app_private"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "app_private"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "app_private"."notify_due_inspections"() from public, anon;
grant execute on function "app_private"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_programs";
create policy bsb_tenant_scope_select on "app_private"."inspection_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_programs";
create policy bsb_tenant_scope_insert on "app_private"."inspection_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_programs";
create policy bsb_tenant_scope_update on "app_private"."inspection_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_programs";
create policy bsb_tenant_scope_delete on "app_private"."inspection_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."inspections";
drop policy if exists bsb_tenant_scope_select on "app_private"."inspections";
create policy bsb_tenant_scope_select on "app_private"."inspections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."inspections";
create policy bsb_tenant_scope_insert on "app_private"."inspections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."inspections";
create policy bsb_tenant_scope_update on "app_private"."inspections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."inspections";
create policy bsb_tenant_scope_delete on "app_private"."inspections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_findings";
create policy bsb_tenant_scope_select on "app_private"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_findings";
create policy bsb_tenant_scope_insert on "app_private"."inspection_findings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_findings";
create policy bsb_tenant_scope_update on "app_private"."inspection_findings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_findings";
create policy bsb_tenant_scope_delete on "app_private"."inspection_findings" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:7a08e6b7b3b4ad6bef4a4792093c3b7ba60d90a2d875e3b4dc4fe421857735a8
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null check ("period_end" >= "period_start"),
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
create policy inspection_programs_read on better_supabase.inspection_programs
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  "number" text not null,
  "kind" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "scope" text,
  "criteria" text,
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  "summary" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("program_id") references "better_supabase"."inspection_programs" ("id") on delete set null
);
create index if not exists inspections_status_idx on "better_supabase"."inspections" ("tenant_id", "status");
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;
create policy inspections_read on better_supabase.inspections
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  "number" integer not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "clause" text,
  "case_id" uuid,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("inspection_id") references "better_supabase"."inspections" ("id") on delete cascade
);
create index if not exists inspection_findings_parent_idx on "better_supabase"."inspection_findings" ("inspection_id");
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
create policy inspection_findings_read on better_supabase.inspection_findings
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "better_supabase"."inspection_programs" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "better_supabase"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "better_supabase"."inspections"%rowtype;
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."tenant_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "better_supabase"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "better_supabase"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "better_supabase"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  raise exception 'install the cases block' using errcode = '55000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
  update "better_supabase"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  null;
  return v_case;
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "better_supabase"."inspections" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "better_supabase"."notify_due_inspections"() from public, anon;
grant execute on function "better_supabase"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
create policy bsb_tenant_scope_select on "better_supabase"."inspections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
create policy bsb_tenant_scope_insert on "better_supabase"."inspections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
create policy bsb_tenant_scope_update on "better_supabase"."inspections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
create policy bsb_tenant_scope_delete on "better_supabase"."inspections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_findings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_findings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_findings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.inspections.api: entry points for the Data API.
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

create or replace function "api"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_inspection_program"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "api"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."approve_inspection_program"(program_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."approve_inspection_program"($1) $$;
revoke execute on function "api"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "api"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "api"."close_inspection_program"(program_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_inspection_program"($1) $$;
revoke execute on function "api"."close_inspection_program"(uuid) from public, anon;
grant execute on function "api"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "api"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inspection_programs"($1) $$;
revoke execute on function "api"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "api"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "api"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_inspection"($1, $2) $$;
revoke execute on function "api"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "api"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_inspection"($1, $2) $$;
revoke execute on function "api"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."start_inspection"(inspection_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_inspection"($1) $$;
revoke execute on function "api"."start_inspection"(uuid) from public, anon;
grant execute on function "api"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "api"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_inspection_finding"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_inspection_finding"($1, $2) $$;
revoke execute on function "api"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_inspection_finding"(finding_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_inspection_finding"($1) $$;
revoke execute on function "api"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "api"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "api"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_inspection_finding_case"($1, $2) $$;
revoke execute on function "api"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "api"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_inspection"($1, $2) $$;
revoke execute on function "api"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "api"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "api"."close_inspection"(inspection_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_inspection"($1) $$;
revoke execute on function "api"."close_inspection"(uuid) from public, anon;
grant execute on function "api"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_inspection"($1, $2) $$;
revoke execute on function "api"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "api"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_inspection"(inspection_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_inspection"($1) $$;
revoke execute on function "api"."get_inspection"(uuid) from public, anon;
grant execute on function "api"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "api"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inspections"($1, $2) $$;
revoke execute on function "api"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."notify_due_inspections"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_inspections"() $$;
revoke execute on function "api"."notify_due_inspections"() from public, anon;
grant execute on function "api"."notify_due_inspections"() to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:c896e34f71f921ec2a758ac44b00827a7fff55657d2c743bacdbffb264003d78
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

-- better_supabase.inspection_programs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspection_programs" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspection_programs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspection_programs" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."inspection_programs" add column if not exists "period_start" date;
alter table "better_supabase"."inspection_programs" add column if not exists "period_end" date check ("period_end" >= "period_start");
alter table "better_supabase"."inspection_programs" add column if not exists "owner_id" uuid;
alter table "better_supabase"."inspection_programs" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed'));
alter table "better_supabase"."inspection_programs" add column if not exists "notes" text;
alter table "better_supabase"."inspection_programs" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."inspection_programs" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspection_programs" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."inspection_programs" enable row level security;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
create policy bsb_inspection_programs_select on better_supabase.inspection_programs
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

-- better_supabase.inspections is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspections" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspections" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "program_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "number" text;
alter table "better_supabase"."inspections" add column if not exists "kind" text;
alter table "better_supabase"."inspections" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."inspections" add column if not exists "scope" text;
alter table "better_supabase"."inspections" add column if not exists "criteria" text;
alter table "better_supabase"."inspections" add column if not exists "auditee_type" text;
alter table "better_supabase"."inspections" add column if not exists "auditee_id" text;
alter table "better_supabase"."inspections" add column if not exists "lead_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "planned_start" date;
alter table "better_supabase"."inspections" add column if not exists "planned_end" date;
alter table "better_supabase"."inspections" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "completed_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled'));
alter table "better_supabase"."inspections" add column if not exists "summary" text;
alter table "better_supabase"."inspections" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."inspections" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspections" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists inspections_status_idx on "better_supabase"."inspections" ("tenant_id", "status");
alter table "better_supabase"."inspections" enable row level security;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;
create policy bsb_inspections_select on better_supabase.inspections
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

-- better_supabase.inspection_findings is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspection_findings" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspection_findings" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "inspection_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "number" integer;
alter table "better_supabase"."inspection_findings" add column if not exists "type" text;
alter table "better_supabase"."inspection_findings" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."inspection_findings" add column if not exists "description" text;
alter table "better_supabase"."inspection_findings" add column if not exists "clause" text;
alter table "better_supabase"."inspection_findings" add column if not exists "case_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."inspection_findings" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspection_findings" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists inspection_findings_parent_idx on "better_supabase"."inspection_findings" ("inspection_id");
alter table "better_supabase"."inspection_findings" enable row level security;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
create policy bsb_inspection_findings_select on better_supabase.inspection_findings
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "better_supabase"."inspection_programs" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "better_supabase"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "better_supabase"."inspections"%rowtype;
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."tenant_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "better_supabase"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "better_supabase"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "better_supabase"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  raise exception 'install the cases block' using errcode = '55000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
  update "better_supabase"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  null;
  return v_case;
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "better_supabase"."inspections" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "better_supabase"."notify_due_inspections"() from public, anon;
grant execute on function "better_supabase"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
create policy bsb_tenant_scope_select on "better_supabase"."inspections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
create policy bsb_tenant_scope_insert on "better_supabase"."inspections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
create policy bsb_tenant_scope_update on "better_supabase"."inspections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
create policy bsb_tenant_scope_delete on "better_supabase"."inspections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_findings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_findings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_findings" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:d68c3169edeab8af616cd6b687bae0a6fb10ed41d4232db03cb9f4db40173357
-- Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null check ("period_end" >= "period_start"),
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
create policy inspection_programs_read on better_supabase.inspection_programs
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "program_id" uuid,
  "number" text not null,
  "kind" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "scope" text,
  "criteria" text,
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  "summary" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "number"),
  foreign key ("program_id") references "better_supabase"."inspection_programs" ("id") on delete set null
);
create index if not exists inspections_status_idx on "better_supabase"."inspections" ("org_id", "status");
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;
create policy inspections_read on better_supabase.inspections
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "inspection_id" uuid not null,
  "number" integer not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "clause" text,
  "case_id" uuid,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("inspection_id") references "better_supabase"."inspections" ("id") on delete cascade
);
create index if not exists inspection_findings_parent_idx on "better_supabase"."inspection_findings" ("inspection_id");
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
create policy inspection_findings_read on better_supabase.inspection_findings
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'the period ends before it starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("org_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."inspection_programs" x set "name" = trim(save_inspection_program.name), "period_start" = save_inspection_program.period_start, "period_end" = save_inspection_program.period_end, "owner_id" = save_inspection_program.owner_id, "notes" = save_inspection_program.notes, "updated_at" = now()
      where x."id" = save_inspection_program.program_id and x."org_id" = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_programs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id;
  if not found then
    raise exception 'inspection program not found' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false) then
    raise exception 'not allowed to manage inspection programs' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes") order by x."period_start" desc), '[]'::jsonb)
  from "better_supabase"."inspection_programs" x
  where x."org_id" = $1 and x."org_id" in (select better_supabase.tenant_ids_with('inspections.read'))
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."inspections" ("org_id", "program_id", "number", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "lead_id", "planned_start", "planned_end")
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from "better_supabase"."inspections" x where x."org_id" = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false) then
    raise exception 'not allowed to change inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'cancelled') then
    raise exception 'a closed inspection can''t change' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row."scope" := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row."criteria" := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row."lead_id" := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row."planned_start" := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row."planned_end" := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update "better_supabase"."inspections" x set "title" = v_row."title", "scope" = v_row."scope", "criteria" = v_row."criteria", "lead_id" = v_row."lead_id", "planned_start" = v_row."planned_start", "planned_end" = v_row."planned_end", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to run inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'only a planned inspection can start' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection "better_supabase"."inspections"%rowtype;
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to add findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings need a running inspection' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  insert into "better_supabase"."inspection_findings" ("org_id", "inspection_id", "number", "type", "title", "description", "clause")
  values (v_inspection."org_id", v_inspection."id", (select coalesce(max(x."number"), 0) + 1 from "better_supabase"."inspection_findings" x where x."inspection_id" = v_inspection."id"), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to change findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if changes ? 'type' then v_row."type" := changes ->> 'type'; end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row."clause" := changes ->> 'clause'; end if;
  update "better_supabase"."inspection_findings" x set "type" = v_row."type", "title" = v_row."title", "description" = v_row."description", "clause" = v_row."clause", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'caseId', v_row."case_id");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspection_findings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to delete findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding "better_supabase"."inspection_findings"%rowtype;
  v_case jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_finding from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id;
  if not found then
    raise exception 'finding not found' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_finding."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to raise findings' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_finding."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  raise exception 'install the cases block' using errcode = '55000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
  update "better_supabase"."inspection_findings" x set "case_id" = (v_case ->> 'id')::uuid, "updated_at" = now() where x."id" = v_finding."id" returning * into v_finding;
  null;
  return v_case;
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text) to authenticated, service_role;;

create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) then
    raise exception 'not allowed to complete inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a running inspection can complete' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'reporting', "completed_at" = now(), "summary" = complete_inspection.summary, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_open uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false) then
    raise exception 'not allowed to close inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'only a reporting inspection can close' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  select array_agg(x."id") into v_open from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id" and x."type" in ('major_nonconformity', 'minor_nonconformity') and x."case_id" is null;
  if v_open is not null then
    raise exception 'nonconformities need a case before closing' using errcode = '22023', hint = 'INSPECTION_FINDINGS_OPEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  update "better_supabase"."inspections" x set "status" = 'cancelled', "summary" = cancel_inspection.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_findings jsonb;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found then
    raise exception 'inspection not found' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.read'), false) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'inspectionId', x."inspection_id", 'number', x."number", 'type', x."type", 'title', x."title", 'description', x."description", 'clause', x."clause", 'caseId', x."case_id") order by x."number"), '[]'::jsonb) into v_findings from "better_supabase"."inspection_findings" x where x."inspection_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditeeType', v_row."auditee_type", 'auditeeId', v_row."auditee_id", 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'summary', v_row."summary") || jsonb_build_object('findings', v_findings);
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditeeType', x."auditee_type", 'auditeeId', x."auditee_id", 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'summary', x."summary") order by x."planned_start" desc nulls last), '[]'::jsonb)
  from "better_supabase"."inspections" x
  where x."org_id" = $1
    and x."org_id" in (select better_supabase.tenant_ids_with('inspections.read'))
    and (not (filters ? 'programId') or x."program_id" = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x."kind" = filters ->> 'kind')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'leadId') or x."lead_id" = (filters ->> 'leadId')::uuid)
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_inspections"()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."inspections" x where x."status" = 'planned' and x."planned_start" is not null and x."planned_start" <= current_date
$$;
revoke execute on function "better_supabase"."notify_due_inspections"() from public, anon;
grant execute on function "better_supabase"."notify_due_inspections"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_programs" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_programs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_programs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_programs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspections";
create policy bsb_tenant_scope_select on "better_supabase"."inspections" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspections";
create policy bsb_tenant_scope_insert on "better_supabase"."inspections" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspections";
create policy bsb_tenant_scope_update on "better_supabase"."inspections" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspections";
create policy bsb_tenant_scope_delete on "better_supabase"."inspections" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_findings" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_findings" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_findings" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block-data inspections
-- @bsb-hash sha256:2c877d673ffd6dbad827ec793bfa52d6ad605faaec97307b2daabb490a96d99f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
