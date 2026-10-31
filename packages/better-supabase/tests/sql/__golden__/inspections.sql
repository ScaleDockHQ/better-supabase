-- ==== alone: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:b80f46e2893386d7f67656e94ad1c6bd9fca70baa8183221752e684883e7cdd0
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("period_end" >= "period_start")
);
create index if not exists "inspection_programs_tenant_idx" on "better_supabase"."inspection_programs" ("tenant_id", "period_start" desc);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
drop policy if exists inspection_programs_read on "better_supabase"."inspection_programs";
create policy inspection_programs_read on "better_supabase"."inspection_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "scope" text check ("scope" is null or length("scope") <= 10000),
  "criteria" text check ("criteria" is null or length("criteria") <= 10000),
  -- The subject audited, such as a supplier or a site.
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "overdue_notified_for" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled')),
  "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict,
  "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  check (("auditee_type" is null) = ("auditee_id" is null)),
  check ("planned_end" is null or "planned_start" is null or "planned_end" >= "planned_start"),
  foreign key ("tenant_id", "program_id") references "better_supabase"."inspection_programs" ("tenant_id", "id") on delete restrict
);
create index if not exists "inspections_tenant_idx" on "better_supabase"."inspections" ("tenant_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "better_supabase"."inspections" ("tenant_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "better_supabase"."inspections" ("tenant_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "better_supabase"."inspections" ("tenant_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "better_supabase"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "better_supabase"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;

create table if not exists "better_supabase"."inspection_members" (
  "inspection_id" uuid not null,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check ("role" in ('lead', 'auditor', 'observer', 'auditee')),
  "created_at" timestamptz not null default now(),
  primary key ("inspection_id", "user_id"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_members_parent_idx" on "better_supabase"."inspection_members" ("tenant_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "better_supabase"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "better_supabase"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "better_supabase"."inspection_members" enable row level security;
revoke all on "better_supabase"."inspection_members" from public, anon, authenticated;
grant select on "better_supabase"."inspection_members" to authenticated;
grant all on "better_supabase"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "better_supabase"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."inspection_role"(uuid) from public, anon;
grant execute on function "better_supabase"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists inspections_read on "better_supabase"."inspections";
create policy inspections_read on "better_supabase"."inspections"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null);
drop policy if exists inspection_members_read on "better_supabase"."inspection_members";
create policy inspection_members_read on "better_supabase"."inspection_members"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  -- 1, 2, 3 within the inspection.
  "number" integer not null check ("number" > 0),
  -- One of options.findingTypes; the functions check it.
  "type" text not null check (length("type") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "clause" text check ("clause" is null or length("clause") <= 200),
  "control_id" uuid,
  "evidence" text check ("evidence" is null or length("evidence") <= 10000),
  "case_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_findings_parent_idx" on "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "better_supabase"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "better_supabase"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
drop policy if exists inspection_findings_read on "better_supabase"."inspection_findings";
create policy inspection_findings_read on "better_supabase"."inspection_findings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "better_supabase"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "better_supabase"."inspection_programs" x
    where x."tenant_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "better_supabase"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."organization_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "better_supabase"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "better_supabase"."inspection_members" ("inspection_id", "tenant_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "better_supabase"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(schedule_inspection.tenant::text || ':inspection', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant;
  v_number := 'AUD-' || v_seq::text;
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_tenant, "better_supabase"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "better_supabase"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id", set_inspection_members.members);
  update "better_supabase"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "better_supabase"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "better_supabase"."inspection_findings" y
  where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "better_supabase"."inspections";
  v_row "better_supabase"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "better_supabase"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."tenant_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  raise exception 'raising a case needs the cases block' using errcode = '0A000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false))) or "better_supabase"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "better_supabase"."inspection_members" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "better_supabase"."inspection_findings" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "better_supabase"."inspection_findings" y
        where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "better_supabase"."notify_overdue_inspections"()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "better_supabase"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_inspections"() to service_role;

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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:e607533afde5cfb38403101c69097194e672961e56cb98d744e9b2df095db742
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("period_end" >= "period_start")
);
create index if not exists "inspection_programs_tenant_idx" on "better_supabase"."inspection_programs" ("tenant_id", "period_start" desc);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
drop policy if exists inspection_programs_read on "better_supabase"."inspection_programs";
create policy inspection_programs_read on "better_supabase"."inspection_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "scope" text check ("scope" is null or length("scope") <= 10000),
  "criteria" text check ("criteria" is null or length("criteria") <= 10000),
  -- The subject audited, such as a supplier or a site.
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "overdue_notified_for" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled')),
  "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict,
  "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  check (("auditee_type" is null) = ("auditee_id" is null)),
  check ("planned_end" is null or "planned_start" is null or "planned_end" >= "planned_start"),
  foreign key ("tenant_id", "program_id") references "better_supabase"."inspection_programs" ("tenant_id", "id") on delete restrict
);
create index if not exists "inspections_tenant_idx" on "better_supabase"."inspections" ("tenant_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "better_supabase"."inspections" ("tenant_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "better_supabase"."inspections" ("tenant_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "better_supabase"."inspections" ("tenant_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "better_supabase"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "better_supabase"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;

create table if not exists "better_supabase"."inspection_members" (
  "inspection_id" uuid not null,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check ("role" in ('lead', 'auditor', 'observer', 'auditee')),
  "created_at" timestamptz not null default now(),
  primary key ("inspection_id", "user_id"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_members_parent_idx" on "better_supabase"."inspection_members" ("tenant_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "better_supabase"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "better_supabase"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "better_supabase"."inspection_members" enable row level security;
revoke all on "better_supabase"."inspection_members" from public, anon, authenticated;
grant select on "better_supabase"."inspection_members" to authenticated;
grant all on "better_supabase"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "better_supabase"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."inspection_role"(uuid) from public, anon;
grant execute on function "better_supabase"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists inspections_read on "better_supabase"."inspections";
create policy inspections_read on "better_supabase"."inspections"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null);
drop policy if exists inspection_members_read on "better_supabase"."inspection_members";
create policy inspection_members_read on "better_supabase"."inspection_members"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  -- 1, 2, 3 within the inspection.
  "number" integer not null check ("number" > 0),
  -- One of options.findingTypes; the functions check it.
  "type" text not null check (length("type") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "clause" text check ("clause" is null or length("clause") <= 200),
  "control_id" uuid references "better_supabase"."controls" ("id") on delete set null,
  "evidence" text check ("evidence" is null or length("evidence") <= 10000),
  "case_id" uuid references "better_supabase"."cases" ("id") on delete set null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_findings_parent_idx" on "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "better_supabase"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "better_supabase"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
drop policy if exists inspection_findings_read on "better_supabase"."inspection_findings";
create policy inspection_findings_read on "better_supabase"."inspection_findings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    perform "better_supabase".emit_event('inspection_program.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.created',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'audit programme created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  else
    select * into v_row from "better_supabase"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "better_supabase"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('inspection_program.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.updated',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'audit programme updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection_program.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.approved',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'audit programme approved',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection_program.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'inspection-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_program.closed',
    category => 'data',
    target_type => 'inspection_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'audit programme closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "better_supabase"."inspection_programs" x
    where x."tenant_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "better_supabase"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."organization_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "better_supabase"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "better_supabase"."inspection_members" ("inspection_id", "tenant_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "better_supabase"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(schedule_inspection.tenant, 'inspection', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(schedule_inspection.tenant, 'inspection', now(), '');
  v_number := better_supabase.format_assigned_number('AUD-{yyyy}-{n:3}', v_seq, now());
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.scheduled',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection scheduled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_tenant, "better_supabase"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "better_supabase"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('inspection.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.updated',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id", set_inspection_members.members);
  update "better_supabase"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.updated',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection team changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.started', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.started',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection started',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "better_supabase"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.completed',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection completed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "better_supabase"."inspection_findings" y
  where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.closed',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_inspection.reason), '')), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.cancelled',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection canceled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_inspection.reason), ''))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "better_supabase"."inspections";
  v_row "better_supabase"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null and not exists (
    select 1 from "better_supabase"."controls" y
    where y."id" = add_inspection_finding.control_id and y."tenant_id"::text = v_inspection."tenant_id"::text
  ) then
    raise exception 'the control is not a control of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "better_supabase"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."tenant_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  if v_row."control_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'assesses', 'inspection', v_row."inspection_id"::text, 'control', v_row."control_id"::text, auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" y
      where y."tenant_id" = v_row."tenant_id" and y."kind" = 'assesses' and y."source_type" = 'inspection'
        and y."source_id" = v_row."inspection_id"::text and y."target_type" = 'control' and y."target_id" = v_row."control_id"::text
    );
  end if;
  perform "better_supabase".emit_event('inspection_finding.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.created',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'finding added',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null and not exists (
    select 1 from "better_supabase"."controls" y
    where y."id" = v_control and y."tenant_id"::text = v_row."tenant_id"::text
  ) then
    raise exception 'the control is not a control of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."control_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'assesses', 'inspection', v_row."inspection_id"::text, 'control', v_row."control_id"::text, auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" y
      where y."tenant_id" = v_row."tenant_id" and y."kind" = 'assesses' and y."source_type" = 'inspection'
        and y."source_id" = v_row."inspection_id"::text and y."target_type" = 'control' and y."target_id" = v_row."control_id"::text
    );
  end if;
  perform "better_supabase".emit_event('inspection_finding.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.updated',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'finding updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('inspection_finding.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.deleted',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'finding deleted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_kind uuid;
  v_case "better_supabase"."cases";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = raise_inspection_finding_case.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to raise a case for this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'the finding already has a case' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select y."id" into v_kind from "better_supabase"."case_kinds" y
  where y."tenant_id"::text = v_row."tenant_id"::text and y."key" = raise_inspection_finding_case.kind and y."archived_at" is null;
  if v_kind is null then
    perform "better_supabase"."ensure_case_kinds"(v_row."tenant_id");
    select y."id" into v_kind from "better_supabase"."case_kinds" y
  where y."tenant_id"::text = v_row."tenant_id"::text and y."key" = raise_inspection_finding_case.kind and y."archived_at" is null;
  end if;
  if v_kind is null then
    raise exception 'no such case kind in this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_case := "better_supabase"."open_case_as"(v_kind, jsonb_build_object(
    'title', left(v_inspection."number" || ': ' || v_row."title", 200),
    'description', v_row."description",
    'source', 'inspection',
    'occurredAt', coalesce(v_inspection."started_at", now()),
    'ownerId', raise_inspection_finding_case.owner_id,
    'originType', 'inspection_finding',
    'originId', v_row."id"::text
  ), auth.uid());
  update "better_supabase"."inspection_findings" x set "case_id" = v_case."id", "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection_finding.case_raised', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'caseId', v_row."case_id"), 'inspection-findings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection_finding.case_raised',
    category => 'data',
    target_type => 'inspection_finding',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'case raised for finding',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'caseId', v_row."case_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false))) or "better_supabase"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "better_supabase"."inspection_members" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "better_supabase"."inspection_findings" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "better_supabase"."inspection_findings" y
        where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      union
      select y."target_id" from "better_supabase"."relations" y
      where y."tenant_id" = v_row."tenant_id" and y."kind" = 'assesses'
        and y."source_type" = 'inspection' and y."source_id" = v_row."id"::text
        and y."target_type" = 'control'
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Notifies a user added to an inspection's team, unless they added themselves.
-- The key keeps a team edit that keeps the user from notifying again.
create or replace function "better_supabase"."inspection_assignment_notice"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
begin
  if new."user_id" is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = new."inspection_id";
  if not found or v_row."status" not in ('planned', 'in_progress') then
    return new;
  end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inspection.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'inspection',
      'subject_id', v_row."id"::text,
      'summary', v_row."number" || ' ' || v_row."title",
      'recipients', to_jsonb(array[new."user_id"]),
      'key', 'inspection.assigned:' || v_row."id"::text || ':' || new."user_id"::text,
      'data', jsonb_build_object('inspectionId', v_row."id", 'role', new."role")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."inspection_assignment_notice"() from public, anon, authenticated;
drop trigger if exists bsb_inspection_assignment on "better_supabase"."inspection_members";
create trigger bsb_inspection_assignment after insert on "better_supabase"."inspection_members"
  for each row execute function "better_supabase"."inspection_assignment_notice"();

-- Reports each planned or running inspection whose planned end has passed, to
-- its lead or, without one, its auditors, once per planned end (the key keeps
-- a repeat run quiet). Run it daily from a job (the inspections.overdue timer).
create or replace function "better_supabase"."notify_overdue_inspections"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
  v_to uuid[];
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."inspections" x
    where x."status" in ('planned', 'in_progress')
      and x."planned_end" < current_date
      and x."overdue_notified_for" is distinct from x."planned_end"
    for update skip locked
  loop
    select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
    where y."inspection_id" = v_row."id" and y."role" = 'lead';
    if cardinality(v_to) = 0 then
      select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
      where y."inspection_id" = v_row."id" and y."role" = 'auditor';
    end if;
    if cardinality(v_to) > 0 then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inspection.overdue',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'inspection',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(v_to),
        'key', 'inspection.overdue:' || v_row."id"::text || ':' || v_row."planned_end"::text,
        'data', jsonb_build_object('inspectionId', v_row."id", 'plannedEnd', v_row."planned_end")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."inspections" x set "overdue_notified_for" = v_row."planned_end" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_inspections"() to service_role;

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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:6944b8703793da2beb5229ae41fe9a37a03af6a86353932939480104cf47125b
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "app_private"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

create table if not exists "app_private"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("period_end" >= "period_start")
);
create index if not exists "inspection_programs_tenant_idx" on "app_private"."inspection_programs" ("tenant_id", "period_start" desc);
alter table "app_private"."inspection_programs" enable row level security;
revoke all on "app_private"."inspection_programs" from public, anon, authenticated;
grant select on "app_private"."inspection_programs" to authenticated;
grant all on "app_private"."inspection_programs" to service_role;
drop policy if exists inspection_programs_read on "app_private"."inspection_programs";
create policy inspection_programs_read on "app_private"."inspection_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "app_private"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "scope" text check ("scope" is null or length("scope") <= 10000),
  "criteria" text check ("criteria" is null or length("criteria") <= 10000),
  -- The subject audited, such as a supplier or a site.
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "overdue_notified_for" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled')),
  "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict,
  "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  check (("auditee_type" is null) = ("auditee_id" is null)),
  check ("planned_end" is null or "planned_start" is null or "planned_end" >= "planned_start"),
  foreign key ("tenant_id", "program_id") references "app_private"."inspection_programs" ("tenant_id", "id") on delete restrict
);
create index if not exists "inspections_tenant_idx" on "app_private"."inspections" ("tenant_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "app_private"."inspections" ("tenant_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "app_private"."inspections" ("tenant_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "app_private"."inspections" ("tenant_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "app_private"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "app_private"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "app_private"."inspections" enable row level security;
revoke all on "app_private"."inspections" from public, anon, authenticated;
grant select on "app_private"."inspections" to authenticated;
grant all on "app_private"."inspections" to service_role;

create table if not exists "app_private"."inspection_members" (
  "inspection_id" uuid not null,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check ("role" in ('lead', 'auditor', 'observer', 'auditee')),
  "created_at" timestamptz not null default now(),
  primary key ("inspection_id", "user_id"),
  foreign key ("tenant_id", "inspection_id") references "app_private"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_members_parent_idx" on "app_private"."inspection_members" ("tenant_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "app_private"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "app_private"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "app_private"."inspection_members" enable row level security;
revoke all on "app_private"."inspection_members" from public, anon, authenticated;
grant select on "app_private"."inspection_members" to authenticated;
grant all on "app_private"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "app_private"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "app_private"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "app_private"."inspection_role"(uuid) from public, anon;
grant execute on function "app_private"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists inspections_read on "app_private"."inspections";
create policy inspections_read on "app_private"."inspections"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("id") is not null);
drop policy if exists inspection_members_read on "app_private"."inspection_members";
create policy inspection_members_read on "app_private"."inspection_members"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("inspection_id") is not null);

create table if not exists "app_private"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  -- 1, 2, 3 within the inspection.
  "number" integer not null check ("number" > 0),
  -- One of options.findingTypes; the functions check it.
  "type" text not null check (length("type") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "clause" text check ("clause" is null or length("clause") <= 200),
  "control_id" uuid,
  "evidence" text check ("evidence" is null or length("evidence") <= 10000),
  "case_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("tenant_id", "inspection_id") references "app_private"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_findings_parent_idx" on "app_private"."inspection_findings" ("tenant_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "app_private"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "app_private"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "app_private"."inspection_findings" enable row level security;
revoke all on "app_private"."inspection_findings" from public, anon, authenticated;
grant select on "app_private"."inspection_findings" to authenticated;
grant all on "app_private"."inspection_findings" to service_role;
drop policy if exists inspection_findings_read on "app_private"."inspection_findings";
create policy inspection_findings_read on "app_private"."inspection_findings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "app_private"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "app_private"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    null;
  else
    select * into v_row from "app_private"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "app_private"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "app_private"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "app_private"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "app_private"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "app_private"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "app_private"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "app_private"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."close_inspection_program"(uuid) from public, anon;
grant execute on function "app_private"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "app_private"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "app_private"."inspection_programs" x
    where x."tenant_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "app_private"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "app_private"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."organization_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "app_private"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "app_private"."inspection_members" ("inspection_id", "tenant_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "app_private"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "app_private"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "app_private"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "app_private"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "app_private"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "app_private"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(schedule_inspection.tenant::text || ':inspection', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "app_private"."inspections" x where x."tenant_id" = schedule_inspection.tenant;
  v_number := 'AUD-' || v_seq::text;
  end if;
  insert into "app_private"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "app_private"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "app_private"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "app_private"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "app_private"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "app_private"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "app_private"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "app_private"."inspection_set_team"(v_row."id", v_tenant, "app_private"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "app_private"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "app_private"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "app_private"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "app_private"."inspection_set_team"(v_row."id", v_row."tenant_id", set_inspection_members.members);
  update "app_private"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "app_private"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "app_private"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."start_inspection"(uuid) from public, anon;
grant execute on function "app_private"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "app_private"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "app_private"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "app_private"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "app_private"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "app_private"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "app_private"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "app_private"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "app_private"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "app_private"."inspection_findings" y
  where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "app_private"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."close_inspection"(uuid) from public, anon;
grant execute on function "app_private"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "app_private"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "app_private"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "app_private"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "app_private"."inspections";
  v_row "app_private"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "app_private"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "app_private"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "app_private"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."tenant_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "app_private"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "app_private"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspection_findings";
  v_inspection "app_private"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "app_private"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "app_private"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "app_private"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspection_findings";
  v_inspection "app_private"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "app_private"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("app_private"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "app_private"."inspection_findings" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "app_private"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "app_private"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  raise exception 'raising a case needs the cases block' using errcode = '0A000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
end;
$$;
revoke execute on function "app_private"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "app_private"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."inspections";
begin
  select * into v_row from "app_private"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false))) or "app_private"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "app_private"."inspection_members" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "app_private"."inspection_findings" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "app_private"."inspection_findings" y
        where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "app_private"."get_inspection"(uuid) from public, anon;
grant execute on function "app_private"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "app_private"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "app_private"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "app_private"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "app_private"."notify_overdue_inspections"()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "app_private"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "app_private"."notify_overdue_inspections"() to service_role;

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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "app_private"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_members";
create policy bsb_tenant_scope_select on "app_private"."inspection_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."inspection_members";
create policy bsb_tenant_scope_insert on "app_private"."inspection_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."inspection_members";
create policy bsb_tenant_scope_update on "app_private"."inspection_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."inspection_members";
create policy bsb_tenant_scope_delete on "app_private"."inspection_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "app_private"."inspection_findings";
create policy bsb_tenant_scope_select on "app_private"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "app_private"."inspection_role"("inspection_id") is not null)
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:406ee39ddee90c338cc4ca9f52d2d589fec1ac8b6eb3de188354b3510ca4d4db
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("period_end" >= "period_start")
);
create index if not exists "inspection_programs_tenant_idx" on "better_supabase"."inspection_programs" ("tenant_id", "period_start" desc);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
drop policy if exists inspection_programs_read on "better_supabase"."inspection_programs";
create policy inspection_programs_read on "better_supabase"."inspection_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "program_id" uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "scope" text check ("scope" is null or length("scope") <= 10000),
  "criteria" text check ("criteria" is null or length("criteria") <= 10000),
  -- The subject audited, such as a supplier or a site.
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "overdue_notified_for" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled')),
  "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict,
  "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  check (("auditee_type" is null) = ("auditee_id" is null)),
  check ("planned_end" is null or "planned_start" is null or "planned_end" >= "planned_start"),
  foreign key ("tenant_id", "program_id") references "better_supabase"."inspection_programs" ("tenant_id", "id") on delete restrict
);
create index if not exists "inspections_tenant_idx" on "better_supabase"."inspections" ("tenant_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "better_supabase"."inspections" ("tenant_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "better_supabase"."inspections" ("tenant_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "better_supabase"."inspections" ("tenant_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "better_supabase"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "better_supabase"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;

create table if not exists "better_supabase"."inspection_members" (
  "inspection_id" uuid not null,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check ("role" in ('lead', 'auditor', 'observer', 'auditee')),
  "created_at" timestamptz not null default now(),
  primary key ("inspection_id", "user_id"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_members_parent_idx" on "better_supabase"."inspection_members" ("tenant_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "better_supabase"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "better_supabase"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "better_supabase"."inspection_members" enable row level security;
revoke all on "better_supabase"."inspection_members" from public, anon, authenticated;
grant select on "better_supabase"."inspection_members" to authenticated;
grant all on "better_supabase"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "better_supabase"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."inspection_role"(uuid) from public, anon;
grant execute on function "better_supabase"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists inspections_read on "better_supabase"."inspections";
create policy inspections_read on "better_supabase"."inspections"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null);
drop policy if exists inspection_members_read on "better_supabase"."inspection_members";
create policy inspection_members_read on "better_supabase"."inspection_members"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "inspection_id" uuid not null,
  -- 1, 2, 3 within the inspection.
  "number" integer not null check ("number" > 0),
  -- One of options.findingTypes; the functions check it.
  "type" text not null check (length("type") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "clause" text check ("clause" is null or length("clause") <= 200),
  "control_id" uuid,
  "evidence" text check ("evidence" is null or length("evidence") <= 10000),
  "case_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("tenant_id", "inspection_id") references "better_supabase"."inspections" ("tenant_id", "id") on delete cascade
);
create index if not exists "inspection_findings_parent_idx" on "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "better_supabase"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "better_supabase"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
drop policy if exists inspection_findings_read on "better_supabase"."inspection_findings";
create policy inspection_findings_read on "better_supabase"."inspection_findings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "better_supabase"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "better_supabase"."inspection_programs" x
    where x."tenant_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "better_supabase"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."organization_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "better_supabase"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "better_supabase"."inspection_members" ("inspection_id", "tenant_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "better_supabase"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(schedule_inspection.tenant::text || ':inspection', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant;
  v_number := 'AUD-' || v_seq::text;
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_tenant, "better_supabase"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "better_supabase"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id", set_inspection_members.members);
  update "better_supabase"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "better_supabase"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "better_supabase"."inspection_findings" y
  where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "better_supabase"."inspections";
  v_row "better_supabase"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "better_supabase"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."tenant_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  raise exception 'raising a case needs the cases block' using errcode = '0A000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false))) or "better_supabase"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "better_supabase"."inspection_members" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "better_supabase"."inspection_findings" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "better_supabase"."inspection_findings" y
        where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "better_supabase"."notify_overdue_inspections"()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "better_supabase"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_inspections"() to service_role;

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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
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

create or replace function "api"."inspection_role"(inspection_id uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inspection_role"($1) $$;
revoke execute on function "api"."inspection_role"(uuid) from public, anon;
grant execute on function "api"."inspection_role"(uuid) to authenticated, service_role;

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

create or replace function "api"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inspection_set_team"($1, $2, $3) $$;
revoke execute on function "api"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

create or replace function "api"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."inspection_team_with_lead"($1, $2) $$;
revoke execute on function "api"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "api"."inspection_team_with_lead"(jsonb, uuid) to service_role;

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

create or replace function "api"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_inspection_members"($1, $2) $$;
revoke execute on function "api"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."start_inspection"(inspection_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_inspection"($1) $$;
revoke execute on function "api"."start_inspection"(uuid) from public, anon;
grant execute on function "api"."start_inspection"(uuid) to authenticated, service_role;

create or replace function "api"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_inspection_checklist"($1, $2, $3) $$;
revoke execute on function "api"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "api"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."complete_inspection"(inspection_id uuid, summary text default null)
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

create or replace function "api"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_inspection"($1, $2) $$;
revoke execute on function "api"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "api"."cancel_inspection"(uuid, text) to authenticated, service_role;

create or replace function "api"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_inspection_finding"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "api"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

create or replace function "api"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_inspection_finding"($1, $2) $$;
revoke execute on function "api"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_inspection_finding"($1) $$;
revoke execute on function "api"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "api"."delete_inspection_finding"(uuid) to authenticated, service_role;

create or replace function "api"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_inspection_finding_case"($1, $2, $3) $$;
revoke execute on function "api"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "api"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."get_inspection"(inspection_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_inspection"($1) $$;
revoke execute on function "api"."get_inspection"(uuid) from public, anon;
grant execute on function "api"."get_inspection"(uuid) to authenticated, service_role;

create or replace function "api"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_inspections"($1, $2) $$;
revoke execute on function "api"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_inspections"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."notify_overdue_inspections"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_overdue_inspections"() $$;
revoke execute on function "api"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "api"."notify_overdue_inspections"() to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:68b3e3287d0b09c6d198860ee24ef67590d72c73caae732271e52cb41ed07416
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

-- better_supabase.inspection_programs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspection_programs" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspection_programs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspection_programs" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."inspection_programs" add column if not exists "period_start" date;
alter table "better_supabase"."inspection_programs" add column if not exists "period_end" date;
alter table "better_supabase"."inspection_programs" add column if not exists "owner_id" uuid;
alter table "better_supabase"."inspection_programs" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed'));
alter table "better_supabase"."inspection_programs" add column if not exists "notes" text check ("notes" is null or length("notes") <= 10000);
alter table "better_supabase"."inspection_programs" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."inspection_programs" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspection_programs" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_inspection_programs_tenant_id_key" on "better_supabase"."inspection_programs" ("tenant_id", "id");
create index if not exists "inspection_programs_tenant_idx" on "better_supabase"."inspection_programs" ("tenant_id", "period_start" desc);
alter table "better_supabase"."inspection_programs" enable row level security;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
drop policy if exists bsb_inspection_programs_read on "better_supabase"."inspection_programs";
create policy bsb_inspection_programs_read on "better_supabase"."inspection_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read')));

-- better_supabase.inspections is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspections" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspections" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "program_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "number" text check (length("number") between 1 and 100);
alter table "better_supabase"."inspections" add column if not exists "sequence" bigint;
alter table "better_supabase"."inspections" add column if not exists "kind" text check (length("kind") between 1 and 63);
alter table "better_supabase"."inspections" add column if not exists "title" text check (length("title") between 1 and 300);
alter table "better_supabase"."inspections" add column if not exists "scope" text check ("scope" is null or length("scope") <= 10000);
alter table "better_supabase"."inspections" add column if not exists "criteria" text check ("criteria" is null or length("criteria") <= 10000);
alter table "better_supabase"."inspections" add column if not exists "auditee_type" text;
alter table "better_supabase"."inspections" add column if not exists "auditee_id" text;
alter table "better_supabase"."inspections" add column if not exists "lead_id" uuid;
alter table "better_supabase"."inspections" add column if not exists "planned_start" date;
alter table "better_supabase"."inspections" add column if not exists "planned_end" date;
alter table "better_supabase"."inspections" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "completed_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."inspections" add column if not exists "overdue_notified_for" date;
alter table "better_supabase"."inspections" add column if not exists "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled'));
alter table "better_supabase"."inspections" add column if not exists "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict;
alter table "better_supabase"."inspections" add column if not exists "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null;
alter table "better_supabase"."inspections" add column if not exists "summary" text check ("summary" is null or length("summary") <= 20000);
alter table "better_supabase"."inspections" add column if not exists "created_by" uuid;
alter table "better_supabase"."inspections" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspections" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_inspections_tenant_number_key" on "better_supabase"."inspections" ("tenant_id", "number");
create unique index if not exists "bsb_inspections_tenant_id_key" on "better_supabase"."inspections" ("tenant_id", "id");
create index if not exists "inspections_tenant_idx" on "better_supabase"."inspections" ("tenant_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "better_supabase"."inspections" ("tenant_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "better_supabase"."inspections" ("tenant_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "better_supabase"."inspections" ("tenant_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "better_supabase"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "better_supabase"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "better_supabase"."inspections" enable row level security;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;

-- better_supabase.inspection_members is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspection_members" add column if not exists "inspection_id" uuid;
alter table "better_supabase"."inspection_members" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspection_members" add column if not exists "user_id" uuid;
alter table "better_supabase"."inspection_members" add column if not exists "role" text check ("role" in ('lead', 'auditor', 'observer', 'auditee'));
alter table "better_supabase"."inspection_members" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_inspection_members_inspection_user_key" on "better_supabase"."inspection_members" ("inspection_id", "user_id");
create index if not exists "inspection_members_parent_idx" on "better_supabase"."inspection_members" ("tenant_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "better_supabase"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "better_supabase"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "better_supabase"."inspection_members" enable row level security;
grant select on "better_supabase"."inspection_members" to authenticated;
grant all on "better_supabase"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "better_supabase"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."inspection_role"(uuid) from public, anon;
grant execute on function "better_supabase"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists bsb_inspections_read on "better_supabase"."inspections";
create policy bsb_inspections_read on "better_supabase"."inspections"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null);
drop policy if exists bsb_inspection_members_read on "better_supabase"."inspection_members";
create policy bsb_inspection_members_read on "better_supabase"."inspection_members"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);

-- better_supabase.inspection_findings is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inspection_findings" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inspection_findings" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "inspection_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "number" integer check ("number" > 0);
alter table "better_supabase"."inspection_findings" add column if not exists "type" text check (length("type") between 1 and 63);
alter table "better_supabase"."inspection_findings" add column if not exists "title" text check (length("title") between 1 and 300);
alter table "better_supabase"."inspection_findings" add column if not exists "description" text check ("description" is null or length("description") <= 10000);
alter table "better_supabase"."inspection_findings" add column if not exists "clause" text check ("clause" is null or length("clause") <= 200);
alter table "better_supabase"."inspection_findings" add column if not exists "control_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "evidence" text check ("evidence" is null or length("evidence") <= 10000);
alter table "better_supabase"."inspection_findings" add column if not exists "case_id" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "created_by" uuid;
alter table "better_supabase"."inspection_findings" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inspection_findings" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_inspection_findings_inspection_number_key" on "better_supabase"."inspection_findings" ("inspection_id", "number");
create index if not exists "inspection_findings_parent_idx" on "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "better_supabase"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "better_supabase"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "better_supabase"."inspection_findings" enable row level security;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
drop policy if exists bsb_inspection_findings_read on "better_supabase"."inspection_findings";
create policy bsb_inspection_findings_read on "better_supabase"."inspection_findings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("tenant_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."tenant_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "better_supabase"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "better_supabase"."inspection_programs" x
    where x."tenant_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "better_supabase"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."organization_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "better_supabase"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "better_supabase"."inspection_members" ("inspection_id", "tenant_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "better_supabase"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(schedule_inspection.tenant::text || ':inspection', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."inspections" x where x."tenant_id" = schedule_inspection.tenant;
  v_number := 'AUD-' || v_seq::text;
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_tenant, "better_supabase"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "better_supabase"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id", set_inspection_members.members);
  update "better_supabase"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "better_supabase"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "better_supabase"."inspection_findings" y
  where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "better_supabase"."inspections";
  v_row "better_supabase"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "better_supabase"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "better_supabase"."inspection_findings" ("tenant_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."tenant_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."tenant_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  raise exception 'raising a case needs the cases block' using errcode = '0A000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false))) or "better_supabase"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "better_supabase"."inspection_members" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "better_supabase"."inspection_findings" y where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "better_supabase"."inspection_findings" y
        where y."tenant_id" = v_row."tenant_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "better_supabase"."notify_overdue_inspections"()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "better_supabase"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_inspections"() to service_role;

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
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_153_inspections.sql
-- better-supabase module: inspections
-- @bsb-block inspections@1 managed
-- @bsb-hash sha256:2cff250bbb6c013ec3b5354d4e06189ec826f26973cfa80f78f2eb8cadad2838
-- Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
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
-- Audits and inspections per organization: programmes, scheduled inspections
-- with a team and a checklist form, findings, and the cases nonconformities
-- open.

create table if not exists "better_supabase"."inspection_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "period_start" date not null,
  "period_end" date not null,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'closed')),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "id"),
  check ("period_end" >= "period_start")
);
create index if not exists "inspection_programs_tenant_idx" on "better_supabase"."inspection_programs" ("org_id", "period_start" desc);
alter table "better_supabase"."inspection_programs" enable row level security;
revoke all on "better_supabase"."inspection_programs" from public, anon, authenticated;
grant select on "better_supabase"."inspection_programs" to authenticated;
grant all on "better_supabase"."inspection_programs" to service_role;
drop policy if exists inspection_programs_read on "better_supabase"."inspection_programs";
create policy inspection_programs_read on "better_supabase"."inspection_programs"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inspections.read')));

create table if not exists "better_supabase"."inspections" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "program_id" uuid,
  -- AUD-2026-001, from the numbering block when it numbers inspections.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "scope" text check ("scope" is null or length("scope") <= 10000),
  "criteria" text check ("criteria" is null or length("criteria") <= 10000),
  -- The subject audited, such as a supplier or a site.
  "auditee_type" text,
  "auditee_id" text,
  "lead_id" uuid,
  "planned_start" date,
  "planned_end" date,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "closed_at" timestamptz,
  "overdue_notified_for" date,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'reporting', 'closed', 'canceled')),
  "checklist_form_id" uuid references "better_supabase"."forms" ("id") on delete restrict,
  "checklist_submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "number"),
  unique ("org_id", "id"),
  check (("auditee_type" is null) = ("auditee_id" is null)),
  check ("planned_end" is null or "planned_start" is null or "planned_end" >= "planned_start"),
  foreign key ("org_id", "program_id") references "better_supabase"."inspection_programs" ("org_id", "id") on delete restrict
);
create index if not exists "inspections_tenant_idx" on "better_supabase"."inspections" ("org_id", "status", "planned_start" desc);
create index if not exists "inspections_program_idx" on "better_supabase"."inspections" ("org_id", "program_id") where "program_id" is not null;
create index if not exists "inspections_lead_idx" on "better_supabase"."inspections" ("org_id", "lead_id") where "lead_id" is not null;
create index if not exists "inspections_auditee_idx" on "better_supabase"."inspections" ("org_id", "auditee_type", "auditee_id") where "auditee_type" is not null;
create index if not exists "inspections_checklist_form_idx" on "better_supabase"."inspections" ("checklist_form_id") where "checklist_form_id" is not null;
create index if not exists "inspections_checklist_submission_idx" on "better_supabase"."inspections" ("checklist_submission_id") where "checklist_submission_id" is not null;
alter table "better_supabase"."inspections" enable row level security;
revoke all on "better_supabase"."inspections" from public, anon, authenticated;
grant select on "better_supabase"."inspections" to authenticated;
grant all on "better_supabase"."inspections" to service_role;

create table if not exists "better_supabase"."inspection_members" (
  "inspection_id" uuid not null,
  "org_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null check ("role" in ('lead', 'auditor', 'observer', 'auditee')),
  "created_at" timestamptz not null default now(),
  primary key ("inspection_id", "user_id"),
  foreign key ("org_id", "inspection_id") references "better_supabase"."inspections" ("org_id", "id") on delete cascade
);
create index if not exists "inspection_members_parent_idx" on "better_supabase"."inspection_members" ("org_id", "inspection_id");
create index if not exists "inspection_members_user_idx" on "better_supabase"."inspection_members" ("user_id", "inspection_id");
-- One lead per inspection; inspections.lead_id names the same user.
create unique index if not exists "inspection_members_lead_key" on "better_supabase"."inspection_members" ("inspection_id") where "role" = 'lead';
alter table "better_supabase"."inspection_members" enable row level security;
revoke all on "better_supabase"."inspection_members" from public, anon, authenticated;
grant select on "better_supabase"."inspection_members" to authenticated;
grant all on "better_supabase"."inspection_members" to service_role;

-- The caller's role on an inspection, or null. Definer, so the read policies
-- can ask it without reading the members table through its own policy.
create or replace function "better_supabase"."inspection_role"(inspection_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."inspection_members" x
  where x."inspection_id" = inspection_role.inspection_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."inspection_role"(uuid) from public, anon;
grant execute on function "better_supabase"."inspection_role"(uuid) to authenticated, service_role;
drop policy if exists inspections_read on "better_supabase"."inspections";
create policy inspections_read on "better_supabase"."inspections"
  for select to authenticated
  using (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null);
drop policy if exists inspection_members_read on "better_supabase"."inspection_members";
create policy inspection_members_read on "better_supabase"."inspection_members"
  for select to authenticated
  using (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);

create table if not exists "better_supabase"."inspection_findings" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "inspection_id" uuid not null,
  -- 1, 2, 3 within the inspection.
  "number" integer not null check ("number" > 0),
  -- One of options.findingTypes; the functions check it.
  "type" text not null check (length("type") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  "clause" text check ("clause" is null or length("clause") <= 200),
  "control_id" uuid,
  "evidence" text check ("evidence" is null or length("evidence") <= 10000),
  "case_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("inspection_id", "number"),
  foreign key ("org_id", "inspection_id") references "better_supabase"."inspections" ("org_id", "id") on delete cascade
);
create index if not exists "inspection_findings_parent_idx" on "better_supabase"."inspection_findings" ("org_id", "inspection_id", "number");
create index if not exists "inspection_findings_control_idx" on "better_supabase"."inspection_findings" ("control_id") where "control_id" is not null;
create index if not exists "inspection_findings_case_idx" on "better_supabase"."inspection_findings" ("case_id") where "case_id" is not null;
alter table "better_supabase"."inspection_findings" enable row level security;
revoke all on "better_supabase"."inspection_findings" from public, anon, authenticated;
grant select on "better_supabase"."inspection_findings" to authenticated;
grant all on "better_supabase"."inspection_findings" to service_role;
drop policy if exists inspection_findings_read on "better_supabase"."inspection_findings";
create policy inspection_findings_read on "better_supabase"."inspection_findings"
  for select to authenticated
  using (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null);


-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function "better_supabase"."save_inspection_program"(tenant uuid, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_inspection_program.tenant is not null and coalesce(better_supabase.can('tenant', save_inspection_program.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    raise exception 'a programme needs a name of 1 to 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    raise exception 'a programme needs a period that ends on or after its start' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(save_inspection_program.notes) > 10000 then
    raise exception 'notes is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if save_inspection_program.program_id is null then
    insert into "better_supabase"."inspection_programs" ("org_id", "name", "period_start", "period_end", "owner_id", "notes")
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, nullif(trim(save_inspection_program.notes), ''))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."inspection_programs" x
    where x."id" = save_inspection_program.program_id and x."org_id" = save_inspection_program.tenant
    for update;
    if not found then
      raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
    end if;
    if v_row."status" = 'closed' then
      raise exception 'the programme is closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    update "better_supabase"."inspection_programs" x set
      "name" = trim(save_inspection_program.name),
      "period_start" = save_inspection_program.period_start,
      "period_end" = save_inspection_program.period_end,
      "owner_id" = save_inspection_program.owner_id,
      "notes" = nullif(trim(save_inspection_program.notes), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_inspection_program"(uuid, text, date, date, uuid, text, uuid) to authenticated, service_role;

-- Approves a draft programme.
create or replace function "better_supabase"."approve_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = approve_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft programme can be approved' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'approved', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."approve_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."approve_inspection_program"(uuid) to authenticated, service_role;

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function "better_supabase"."close_inspection_program"(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_programs" x where x."id" = close_inspection_program.program_id for update;
  if not found then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to manage audit programmes' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the programme is already closed' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_programs" x set "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'ownerId', v_row."owner_id", 'status', v_row."status", 'notes', v_row."notes", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection_program"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection_program"(uuid) to authenticated, service_role;

-- The organization's programmes, the latest period first.
create or replace function "better_supabase"."list_inspection_programs"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspection_programs.tenant is not null and coalesce(better_supabase.can('tenant', list_inspection_programs.tenant, 'inspections.read'), false))) then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'name', x."name", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'ownerId', x."owner_id", 'status', x."status", 'notes', x."notes", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."name")
    from "better_supabase"."inspection_programs" x
    where x."org_id" = list_inspection_programs.tenant and x."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspection_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."list_inspection_programs"(uuid) to authenticated, service_role;

-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function "better_supabase"."inspection_set_team"(inspection_id uuid, tenant uuid, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'members must be a list' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', '') not in ('lead', 'auditor', 'observer', 'auditee')
  ) then
    raise exception 'each member needs a userId and a role of lead, auditor, observer or auditee' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    raise exception 'an inspection has one lead' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "better_supabase"."memberships" y
      where y."org_id" = inspection_set_team.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every member must belong to the organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  delete from "better_supabase"."inspection_members" x where x."inspection_id" = inspection_set_team.inspection_id;
  insert into "better_supabase"."inspection_members" ("inspection_id", "org_id", "user_id", "role")
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
revoke execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_set_team"(uuid, uuid, jsonb) to service_role;

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function "better_supabase"."inspection_team_with_lead"(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
revoke execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."inspection_team_with_lead"(jsonb, uuid) to service_role;

-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function "better_supabase"."schedule_inspection"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."org_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."org_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(schedule_inspection.tenant::text || ':inspection', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."inspections" x where x."org_id" = schedule_inspection.tenant;
  v_number := 'AUD-' || v_seq::text;
  end if;
  insert into "better_supabase"."inspections" ("org_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."org_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."schedule_inspection"(uuid, jsonb) to authenticated, service_role;

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."update_inspection"(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = update_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  v_tenant := v_row."org_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := coalesce(update_inspection.changes ->> 'kind', v_row."kind");
  v_title := case when update_inspection.changes ? 'title' then trim(update_inspection.changes ->> 'title') else v_row."title" end;
  v_program := case when update_inspection.changes ? 'programId' then nullif(update_inspection.changes ->> 'programId', '')::uuid else v_row."program_id" end;
  v_start := case when update_inspection.changes ? 'plannedStart' then nullif(update_inspection.changes ->> 'plannedStart', '')::date else v_row."planned_start" end;
  v_end := case when update_inspection.changes ? 'plannedEnd' then nullif(update_inspection.changes ->> 'plannedEnd', '')::date else v_row."planned_end" end;
  v_form := case when update_inspection.changes ? 'checklistFormId' then nullif(update_inspection.changes ->> 'checklistFormId', '')::uuid else v_row."checklist_form_id" end;
  v_auditee_type := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'type', '') else v_row."auditee_type" end;
  v_auditee_id := case when update_inspection.changes ? 'auditee' then nullif(update_inspection.changes -> 'auditee' ->> 'id', '') else v_row."auditee_id" end;
  if v_form is distinct from v_row."checklist_form_id" and v_row."status" <> 'planned' then
    raise exception 'the checklist form changes only before the inspection starts' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(update_inspection.changes ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if update_inspection.changes ? 'fields' and jsonb_typeof(update_inspection.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."org_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."org_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set
    "program_id" = v_program,
    "kind" = v_kind,
    "title" = v_title,
    "scope" = case when update_inspection.changes ? 'scope' then nullif(trim(update_inspection.changes ->> 'scope'), '') else x."scope" end,
    "criteria" = case when update_inspection.changes ? 'criteria' then nullif(trim(update_inspection.changes ->> 'criteria'), '') else x."criteria" end,
    "auditee_type" = v_auditee_type,
    "auditee_id" = v_auditee_id,
    "planned_start" = v_start,
    "planned_end" = v_end,
    "checklist_form_id" = v_form,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_tenant, "better_supabase"."inspection_team_with_lead"(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role")), '[]'::jsonb) from "better_supabase"."inspection_members" y where y."inspection_id" = v_row."id"),
      (update_inspection.changes ->> 'leadId')::uuid));
    update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection"(uuid, jsonb) to authenticated, service_role;

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function "better_supabase"."set_inspection_members"(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_lead uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = set_inspection_members.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to change this inspection''s team' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'a closed or canceled inspection takes no changes' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."org_id", set_inspection_members.members);
  update "better_supabase"."inspections" x set "lead_id" = v_lead, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_inspection_members"(uuid, jsonb) to authenticated, service_role;

-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function "better_supabase"."start_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_submission jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = start_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to start this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if v_row."checklist_form_id" is not null and v_row."checklist_submission_id" is null then
    v_submission := "better_supabase"."form_submission_save"(v_row."checklist_form_id", '{}'::jsonb, 'inspection', v_row."id"::text, auth.uid(), 'member', true, null);
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'in_progress',
    "started_at" = now(),
    "checklist_submission_id" = coalesce((v_submission ->> 'id')::uuid, x."checklist_submission_id"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."start_inspection"(uuid) to authenticated, service_role;

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function "better_supabase"."save_inspection_checklist"(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_respondent uuid;
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = save_inspection_checklist.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to fill in this checklist' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the checklist is filled in while the inspection is in progress' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_submission_id" is null then
    raise exception 'the inspection has no checklist' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select x."respondent_id" into v_respondent from "better_supabase"."form_submissions" x
  where x."id" = v_row."checklist_submission_id";
  return "better_supabase"."form_submission_save"(v_row."checklist_form_id", save_inspection_checklist.answers, 'inspection', v_row."id"::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row."checklist_submission_id");
end;
$$;
revoke execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_inspection_checklist"(uuid, jsonb, boolean) to authenticated, service_role;

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function "better_supabase"."complete_inspection"(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = complete_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to complete this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'reporting')::text;
  end if;
  if length(complete_inspection.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_row."checklist_form_id" is not null and not exists (
    select 1 from "better_supabase"."form_submissions" y
    where y."id" = v_row."checklist_submission_id" and y."status"::text in ('submitted', 'accepted')
  ) then
    raise exception 'submit the checklist before completing the inspection' using errcode = '55000', hint = 'INSPECTION_CHECKLIST_INCOMPLETE';
  end if;
  update "better_supabase"."inspections" x set
    "status" = 'reporting',
    "completed_at" = now(),
    "summary" = coalesce(nullif(trim(complete_inspection.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_inspection"(uuid, text) to authenticated, service_role;

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function "better_supabase"."close_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_open jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = close_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_row."id") in ('lead'), false))) then
    raise exception 'not allowed to close this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'reporting' then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'closed' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'closed')::text;
  end if;
  select jsonb_agg(y."id" order by y."number") into v_open from "better_supabase"."inspection_findings" y
  where y."org_id" = v_row."org_id" and y."inspection_id" = v_row."id"
    and y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]) and y."case_id" is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."inspections" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."close_inspection"(uuid) to authenticated, service_role;

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function "better_supabase"."cancel_inspection"(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = cancel_inspection.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.manage'), false))) then
    raise exception 'not allowed to cancel inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_row."status" in ('closed', 'canceled') then
    raise exception 'the inspection can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if length(cancel_inspection.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspections" x set "status" = 'canceled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_inspection"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_inspection"(uuid, text) to authenticated, service_role;


-- Adds a finding to an inspection in progress or reporting, as its lead or an
-- auditor. type is one of options.findingTypes; control_id names the
-- compliance control it concerns, which the inspection then assesses.
create or replace function "better_supabase"."add_inspection_finding"(inspection_id uuid, type text, title text, description text default null, clause text default null, control_id uuid default null, evidence text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_inspection "better_supabase"."inspections";
  v_row "better_supabase"."inspection_findings";
  v_type text := add_inspection_finding.type;
  v_title text := trim(add_inspection_finding.title);
  v_number integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = add_inspection_finding.inspection_id for update;
  if not found then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."org_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to add findings to this inspection' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.description) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.clause) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(add_inspection_finding.evidence) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if add_inspection_finding.control_id is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_finding_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using add_inspection_finding.inspection_id, jsonb_build_object('type', add_inspection_finding.type, 'title', add_inspection_finding.title, 'controlId', add_inspection_finding.control_id);
    end if;
  end;
  select coalesce(max(y."number"), 0) + 1 into v_number from "better_supabase"."inspection_findings" y where y."inspection_id" = v_inspection."id";
  insert into "better_supabase"."inspection_findings" ("org_id", "inspection_id", "number", "type", "title", "description", "clause", "evidence", "control_id", "created_by")
  values (v_inspection."org_id", v_inspection."id", v_number, v_type, v_title, nullif(trim(add_inspection_finding.description), ''), nullif(trim(add_inspection_finding.clause), ''), nullif(trim(add_inspection_finding.evidence), ''), add_inspection_finding.control_id, auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_finding_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_inspection_finding"(uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- Changes a finding's type, title, description, clause, controlId or evidence.
create or replace function "better_supabase"."update_inspection_finding"(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
  v_type text;
  v_title text;
  v_control uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = update_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."org_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to change this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if jsonb_typeof(update_inspection_finding.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_type := coalesce(update_inspection_finding.changes ->> 'type', v_row."type");
  v_title := case when update_inspection_finding.changes ? 'title' then trim(update_inspection_finding.changes ->> 'title') else v_row."title" end;
  v_control := case when update_inspection_finding.changes ? 'controlId' then nullif(update_inspection_finding.changes ->> 'controlId', '')::uuid else v_row."control_id" end;
  if v_type is null or not (v_type = any (array['major_nonconformity', 'minor_nonconformity', 'observation', 'opportunity', 'positive']::text[])) then
    raise exception 'the type is not one of options.findingTypes' using errcode = '22023', hint = 'INSPECTION_FINDING_TYPE_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a finding needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'description')) > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'clause')) > 200 then
    raise exception 'clause is at most 200 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length((update_inspection_finding.changes ->> 'evidence')) > 10000 then
    raise exception 'evidence is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_control is not null then
    raise exception 'controlId needs the compliance block' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  update "better_supabase"."inspection_findings" x set
    "type" = v_type,
    "title" = v_title,
    "description" = case when update_inspection_finding.changes ? 'description' then nullif(trim(update_inspection_finding.changes ->> 'description'), '') else x."description" end,
    "clause" = case when update_inspection_finding.changes ? 'clause' then nullif(trim(update_inspection_finding.changes ->> 'clause'), '') else x."clause" end,
    "evidence" = case when update_inspection_finding.changes ? 'evidence' then nullif(trim(update_inspection_finding.changes ->> 'evidence'), '') else x."evidence" end,
    "control_id" = v_control,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_inspection_finding"(uuid, jsonb) to authenticated, service_role;

-- Deletes a finding that has no case.
create or replace function "better_supabase"."delete_inspection_finding"(finding_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspection_findings";
  v_inspection "better_supabase"."inspections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inspection_findings" x where x."id" = delete_inspection_finding.finding_id for update;
  if not found then
    raise exception 'no such finding' using errcode = 'P0002', hint = 'INSPECTION_FINDING_NOT_FOUND';
  end if;
  select * into v_inspection from "better_supabase"."inspections" x where x."id" = v_row."inspection_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_inspection."org_id" is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_inspection."org_id", 'inspections.write'), false) and coalesce("better_supabase"."inspection_role"(v_inspection."id") in ('lead', 'auditor'), false))) then
    raise exception 'not allowed to delete this finding' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_inspection."status" not in ('in_progress', 'reporting') then
    raise exception 'findings change while the inspection is in progress or reporting' using errcode = '55000', hint = 'INSPECTION_STATUS_INVALID';
  end if;
  if v_row."case_id" is not null then
    raise exception 'a finding with a case can''t be deleted' using errcode = '55000', hint = 'INSPECTION_FINDING_HAS_CASE';
  end if;
  delete from "better_supabase"."inspection_findings" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'inspectionId', v_row."inspection_id", 'number', v_row."number", 'type', v_row."type", 'title', v_row."title", 'description', v_row."description", 'clause', v_row."clause", 'controlId', v_row."control_id", 'evidence', v_row."evidence", 'caseId', v_row."case_id", 'needsCase', v_row."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_inspection_finding"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_inspection_finding"(uuid) to authenticated, service_role;

-- Opens a case of kind (default finding) for a finding, linked back to it, as
-- the inspection's lead or an auditor. The case's own rules then apply.
create or replace function "better_supabase"."raise_inspection_finding_case"(finding_id uuid, kind text default 'finding', owner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  raise exception 'raising a case needs the cases block' using errcode = '0A000', hint = 'INSPECTION_CASES_NOT_INSTALLED';
end;
$$;
revoke execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."raise_inspection_finding_case"(uuid, text, uuid) to authenticated, service_role;


-- An inspection with its team, its findings, its checklist and the controls
-- it assesses. Readers of inspections and the inspection's members see it.
create or replace function "better_supabase"."get_inspection"(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
begin
  select * into v_row from "better_supabase"."inspections" x where x."id" = get_inspection.inspection_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'inspections.read'), false))) or "better_supabase"."inspection_role"(v_row."id") is not null) then
    raise exception 'no such inspection' using errcode = 'P0002', hint = 'INSPECTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', y."user_id", 'role', y."role", 'createdAt', y."created_at")
        order by case y."role" when 'lead' then 0 when 'auditor' then 1 when 'auditee' then 2 else 3 end, y."created_at")
      from "better_supabase"."inspection_members" y where y."org_id" = v_row."org_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'findings', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'inspectionId', y."inspection_id", 'number', y."number", 'type', y."type", 'title', y."title", 'description', y."description", 'clause', y."clause", 'controlId', y."control_id", 'evidence', y."evidence", 'caseId', y."case_id", 'needsCase', y."type" = any (array['major_nonconformity', 'minor_nonconformity']::text[]), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."number")
      from "better_supabase"."inspection_findings" y where y."org_id" = v_row."org_id" and y."inspection_id" = v_row."id"
    ), '[]'::jsonb),
    'checklist', case when v_row."checklist_form_id" is null then null else jsonb_build_object(
      'formId', v_row."checklist_form_id",
      'submissionId', v_row."checklist_submission_id",
      'status', (select y."status" from "better_supabase"."form_submissions" y where y."id" = v_row."checklist_submission_id")
    ) end,
    'assessedControls', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'title', "better_supabase"."subject_title"('control', c.id)) order by c.id)
      from (
        select y."control_id"::text as id from "better_supabase"."inspection_findings" y
        where y."org_id" = v_row."org_id" and y."inspection_id" = v_row."id" and y."control_id" is not null
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_inspection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_inspection"(uuid) to authenticated, service_role;

-- The organization's inspections, the latest planned first. filters is
-- { programId, kind, status, leadId, from, to (on the planned start),
-- auditeeType, auditeeId, search, limit, offset }. Without inspections.read
-- the caller sees only the inspections they are a member of.
create or replace function "better_supabase"."list_inspections"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."planned_start" desc nulls last, x."sequence" desc)
    from (
      select * from "better_supabase"."inspections" x
      where x."org_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      order by x."planned_start" desc nulls last, x."sequence" desc
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_inspections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_inspections"(uuid, jsonb) to authenticated, service_role;


-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "better_supabase"."notify_overdue_inspections"()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "better_supabase"."notify_overdue_inspections"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_inspections"() to service_role;

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
    or (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("id") is not null)
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
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_members" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_insert on "better_supabase"."inspection_members" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_update on "better_supabase"."inspection_members" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inspection_members";
create policy bsb_tenant_scope_delete on "better_supabase"."inspection_members" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."inspection_findings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inspection_findings";
create policy bsb_tenant_scope_select on "better_supabase"."inspection_findings" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (("org_id" in (select better_supabase.tenant_ids_with('inspections.read'))) or "better_supabase"."inspection_role"("inspection_id") is not null)
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_153_inspections.sql
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
