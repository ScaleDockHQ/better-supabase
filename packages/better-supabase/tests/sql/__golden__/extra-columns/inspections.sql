-- ==== schema supabase/schemas/900_better_supabase_146_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:80a073fde4eb1751690468ae83f104b1fd869b8b57a28f3e51f65e54e150d6b0
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
alter table "better_supabase"."inspections" add column if not exists "app_note" text;
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

-- ==== data supabase/better-supabase-data/900_better_supabase_146_inspections.sql
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
