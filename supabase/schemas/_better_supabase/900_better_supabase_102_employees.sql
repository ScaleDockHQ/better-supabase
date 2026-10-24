-- better-supabase module: employees
-- @bsb-block employees@2 managed
-- Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-tracking, time entries carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Employees: the people an organization employs, with or without an
-- account, their manager, team and status; private details and contracts
-- behind employees.view_sensitive.

create table if not exists "better_supabase"."employees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "name" text not null check (length(trim("name")) between 1 and 200),
  "email" text check ("email" is null or length("email") <= 320),
  "job_title" text check ("job_title" is null or length("job_title") <= 200),
  "team_id" uuid,
  "manager_id" uuid references "better_supabase"."employees" ("id") on delete set null,
  "employment_type" text not null default 'employee',
  "status" text not null default 'preboarding' check ("status" in ('preboarding', 'active', 'on_leave', 'offboarded')),
  "start_date" date,
  "end_date" date,
  "offboard_reason" text,
  "origin_type" text,
  "origin_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("manager_id" is null or "manager_id" <> "id"),
  check ("end_date" is null or "start_date" is null or "end_date" >= "start_date"),
  check (("origin_type" is null) = ("origin_id" is null))
);
create unique index if not exists employees_user_idx on "better_supabase"."employees" ("tenant_id", "user_id") where "user_id" is not null;
create index if not exists employees_account_idx on "better_supabase"."employees" ("user_id") where "user_id" is not null;
create unique index if not exists employees_origin_idx on "better_supabase"."employees" ("tenant_id", "origin_type", "origin_id") where "origin_id" is not null;
create index if not exists employees_tenant_status_idx on "better_supabase"."employees" ("tenant_id", "status");
create index if not exists employees_manager_idx on "better_supabase"."employees" ("manager_id") where "manager_id" is not null;
alter table "better_supabase"."employees" enable row level security;
revoke all on "better_supabase"."employees" from anon, authenticated;
grant select on "better_supabase"."employees" to authenticated;
grant all on "better_supabase"."employees" to service_role;
drop policy if exists employees_read on "better_supabase"."employees";
create policy employees_read on "better_supabase"."employees" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()));

-- Private details stay out of the directory: readable with
-- employees.view_sensitive and by the employee.
create table if not exists "better_supabase"."employee_private_details" (
  "employee_id" uuid primary key references "better_supabase"."employees" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid,
  "national_id" text check ("national_id" is null or length("national_id") <= 64),
  "iban" text check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$'),
  "birth_date" date,
  "personal_email" text check ("personal_email" is null or length("personal_email") <= 320),
  "phone" text check ("phone" is null or length("phone") <= 40),
  "address" jsonb check ("address" is null or jsonb_typeof("address") = 'object'),
  "emergency_contacts" jsonb not null default '[]' check (jsonb_typeof("emergency_contacts") = 'array'),
  "offboarded_at" timestamptz,
  "anonymized_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  "updated_by" uuid
);
create index if not exists employee_private_details_user_idx on "better_supabase"."employee_private_details" ("user_id") where "user_id" is not null;
alter table "better_supabase"."employee_private_details" enable row level security;
revoke all on "better_supabase"."employee_private_details" from anon, authenticated;
grant select on "better_supabase"."employee_private_details" to authenticated;
grant all on "better_supabase"."employee_private_details" to service_role;
drop policy if exists employee_private_details_read on "better_supabase"."employee_private_details";
create policy employee_private_details_read on "better_supabase"."employee_private_details" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.view_sensitive')) or "user_id" = (select auth.uid()));

-- Contract history: a new contract ends the one before it, and rows are
-- never edited. Salary is in minor units of its currency.
create table if not exists "better_supabase"."employee_contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "employee_id" uuid not null references "better_supabase"."employees" ("id") on delete cascade,
  "starts_on" date not null,
  "ends_on" date,
  "hours_per_week" numeric(5, 2) check ("hours_per_week" is null or ("hours_per_week" > 0 and "hours_per_week" <= 168)),
  "salary" bigint check ("salary" is null or "salary" >= 0),
  "currency" text check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "salary_period" text check ("salary_period" is null or "salary_period" in ('hour', 'week', 'month', 'year')),
  "note" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  check (("salary" is null) = ("currency" is null))
);
create index if not exists employee_contracts_employee_idx on "better_supabase"."employee_contracts" ("employee_id", "starts_on" desc);
alter table "better_supabase"."employee_contracts" enable row level security;
revoke all on "better_supabase"."employee_contracts" from anon, authenticated;
grant select on "better_supabase"."employee_contracts" to authenticated;
grant all on "better_supabase"."employee_contracts" to service_role;
drop policy if exists employee_contracts_read on "better_supabase"."employee_contracts";
create policy employee_contracts_read on "better_supabase"."employee_contracts" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('employees.view_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())));

-- A manager is an employee of the same organization and never one of the
-- employee's own reports, so the org chart stays a tree.
create or replace function better_supabase.bsb_employee_manager_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_employee_manager_guard() from public, anon, authenticated;
drop trigger if exists bsb_employee_manager_guard on "better_supabase"."employees";
create trigger bsb_employee_manager_guard before insert or update of "manager_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_manager_guard();

-- The private details carry the employee's user, so the employee reads them.
create or replace function better_supabase.bsb_employee_user_mirror()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_employee_user_mirror() from public, anon, authenticated;
drop trigger if exists bsb_employee_user_mirror on "better_supabase"."employees";
create trigger bsb_employee_user_mirror after update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_employee_user_mirror();

-- Creates an employee. attrs: name (required), email, userId, jobTitle,
-- teamId, managerId, employmentType, status, startDate, endDate, origin
-- ({ type, id }) and the extra columns. With an origin, creating again
-- returns the same employee. The status defaults to preboarding before the
-- start date and active from it.
create or replace function "better_supabase"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'employee', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'employee' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('employee.created', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'managerId', v_row."manager_id", 'status', v_row."status"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_employee"(uuid, jsonb) to authenticated, service_role;

-- Applies a batch of { employeeId, field, value } changes, each on its own:
-- a change that fails is rejected with its reason and the others stay.
-- status takes preboarding, active or on_leave; setting it on an
-- offboarded employee rehires them. Returns { accepted: [{ employeeId,
-- field }], rejected: [{ employeeId, field, hint, reason }] }.
create or replace function "better_supabase"."update_employees"(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false));
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        null;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fromManagerId', v_was."manager_id", 'toManagerId', v_row."manager_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'employeeId')::uuid = v_row."id")), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_employees"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_employees"(jsonb) to authenticated, service_role;

-- Ends an employment: the status becomes offboarded and the end date is
-- set (today by default). The employee's reports move to their manager.
-- Offboarding an offboarded employee returns them unchanged.
create or replace function "better_supabase"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  perform "better_supabase".emit_event('employee.offboarded', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'endDate', v_row."end_date", 'reason', v_row."offboard_reason"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."offboard_employee"(uuid, date, text) to authenticated, service_role;

-- The org chart under root, or under every employee without a manager when
-- root is null: current employees with their depth and number of direct
-- reports, ordered for display. Without employees.read the caller sees
-- the chart under themselves or under one of their reports.
create or replace function "better_supabase"."org_chart"(tenant uuid, root uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', org_chart.tenant, 'employees.read'), false) or (org_chart.root is not null and exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = org_chart.root
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid()))) then
    raise exception 'not allowed to read the org chart' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 0, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."tenant_id" = org_chart.tenant and x."status" <> 'offboarded'
        and case when org_chart.root is null then x."manager_id" is null else x."id" = org_chart.root end
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."org_chart"(uuid, uuid) to authenticated, service_role;

-- A manager's current reports: direct ones (depth 1), or everyone under
-- them with indirect. Managers read their own reports without
-- employees.read.
create or replace function "better_supabase"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."employees" x where x."id" = reports_of.manager;
  if v_tenant is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = reports_of.manager
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (
    with recursive tree (id, depth, path) as (
      select x."id", 1, array[lower(x."name"), x."id"::text]
      from "better_supabase"."employees" x
      where x."manager_id" = reports_of.manager and x."status" <> 'offboarded'
      union all
      select c."id", tree.depth + 1, tree.path || array[lower(c."name"), c."id"::text]
      from "better_supabase"."employees" c join tree on c."manager_id" = tree.id
      where coalesce(reports_of.indirect, false) and c."status" <> 'offboarded' and tree.depth < 100
    )
    select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('depth', tree.depth, 'direct_reports', (select count(*) from "better_supabase"."employees" r where r."manager_id" = x."id" and r."status" <> 'offboarded')) order by tree.path), '[]'::jsonb)
    from tree join "better_supabase"."employees" x on x."id" = tree.id
  );
end;
$$;
revoke execute on function "better_supabase"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."reports_of"(uuid, boolean) to authenticated, service_role;

-- The employee for a hired application, in preboarding: the name comes from
-- the candidate's record in config.records, and the job title, team and
-- employment type from the job. attrs overrides any of them. Calling it
-- again returns the same employee, and with the relations module the
-- employee is created_from the application.
create or replace function "better_supabase"."employee_from_application"(application uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."job_openings";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', (case v_application."candidate_type"
      when 'message' then (select s."body"::text from "better_supabase"."messages" s where s."id" = (v_application."candidate_id")::uuid)
      when 'conversation' then (select s."title"::text from "better_supabase"."conversations" s where s."id" = (v_application."candidate_id")::uuid)
      when 'channel' then (select s."name"::text from "better_supabase"."channels" s where s."id" = (v_application."candidate_id")::uuid)
      when 'company' then (select s."name"::text from "better_supabase"."companies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'person' then (select s."name"::text from "better_supabase"."people" s where s."id" = (v_application."candidate_id")::uuid)
      when 'deal' then (select s."name"::text from "better_supabase"."deals" s where s."id" = (v_application."candidate_id")::uuid)
      when 'course' then (select s."title"::text from "better_supabase"."courses" s where s."id" = (v_application."candidate_id")::uuid)
      when 'post' then (select s."title"::text from "better_supabase"."posts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'engagement' then (select s."title"::text from "better_supabase"."engagements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'quote' then (select s."title"::text from "better_supabase"."quotes" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_item' then (select s."title"::text from "better_supabase"."work_items" s where s."id" = (v_application."candidate_id")::uuid)
      when 'employee' then (select s."name"::text from "better_supabase"."employees" s where s."id" = (v_application."candidate_id")::uuid)
      when 'invoice' then (select s."title"::text from "better_supabase"."invoices" s where s."id" = (v_application."candidate_id")::uuid)
      when 'ledger_account' then (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product' then (select s."title"::text from "better_supabase"."products" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product_variant' then (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (v_application."candidate_id")::uuid)
      when 'order' then (select s."number"::text from "better_supabase"."orders" s where s."id" = (v_application."candidate_id")::uuid)
      when 'calendar_event' then (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (v_application."candidate_id")::uuid)
      when 'booking' then (select s."customer_name"::text from "better_supabase"."bookings" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset' then (select s."name"::text from "better_supabase"."assets" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset_location' then (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (v_application."candidate_id")::uuid)
      when 'lease' then (select s."title"::text from "better_supabase"."lease_agreements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_report' then (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_line' then (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (v_application."candidate_id")::uuid)
      when 'donation_fund' then (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_order' then (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (v_application."candidate_id")::uuid)
      when 'shipment' then (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (v_application."candidate_id")::uuid)
      when 'contract' then (select s."title"::text from "better_supabase"."contracts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'control' then (select s."title"::text from "better_supabase"."controls" s where s."id" = (v_application."candidate_id")::uuid)
      when 'policy' then (select s."title"::text from "better_supabase"."policies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'incident' then (select s."title"::text from "better_supabase"."incidents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'content_entry' then (select s."title"::text from "better_supabase"."content_entries" s where s."id" = (v_application."candidate_id")::uuid)
      when 'form' then (select s."title"::text from "better_supabase"."forms" s where s."id" = (v_application."candidate_id")::uuid)
      when 'document' then (select s."name"::text from "better_supabase"."documents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'customer' then (select s."name"::text from "public"."customers" s where s."id" = (v_application."candidate_id")::uuid)
      when 'drive_node' then (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (v_application."candidate_id")::uuid)
      when 'project' then (select s."name"::text from "public"."projects" s where s."id" = (v_application."candidate_id")::uuid)
      when 'task' then (select s."title"::text from "public"."tasks" s where s."id" = (v_application."candidate_id")::uuid)
      else null::text
    end),
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$$;
revoke execute on function "better_supabase"."employee_from_application"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."employee_from_application"(uuid, jsonb) to authenticated, service_role;

-- An employee's private details, or null when none are saved.
create or replace function "better_supabase"."employee_private_details"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.view_sensitive'), false) or v_employee."user_id" = auth.uid()) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."employee_private_details" x where x."employee_id" = v_employee."id";
  if v_row."employee_id" is null then
    return null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."employee_private_details"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_private_details"(uuid) to authenticated, service_role;

-- Saves the keys attrs sets: nationalId, iban, birthDate, personalEmail,
-- phone, address (an object) and emergencyContacts (a list); null clears
-- one. The employee edits their own details too.
create or replace function "better_supabase"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_private_details";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = save_employee_private_details.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.view_sensitive'), false) or v_employee."user_id" = auth.uid()) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(save_employee_private_details.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end if;
  insert into "better_supabase"."employee_private_details" ("employee_id", "tenant_id", "user_id")
  values (v_employee."id", v_employee."tenant_id", v_employee."user_id")
  on conflict ("employee_id") do nothing;
  begin
    update "better_supabase"."employee_private_details" x set "national_id" = case when save_employee_private_details.attrs ? 'nationalId' then nullif(trim(save_employee_private_details.attrs ->> 'nationalId'), '') else x."national_id" end,
      "iban" = case when save_employee_private_details.attrs ? 'iban' then nullif(upper(replace(save_employee_private_details.attrs ->> 'iban', ' ', '')), '') else x."iban" end,
      "birth_date" = case when save_employee_private_details.attrs ? 'birthDate' then (save_employee_private_details.attrs ->> 'birthDate')::date else x."birth_date" end,
      "personal_email" = case when save_employee_private_details.attrs ? 'personalEmail' then nullif(trim(save_employee_private_details.attrs ->> 'personalEmail'), '') else x."personal_email" end,
      "phone" = case when save_employee_private_details.attrs ? 'phone' then nullif(trim(save_employee_private_details.attrs ->> 'phone'), '') else x."phone" end,
      "address" = case when save_employee_private_details.attrs ? 'address' then case when jsonb_typeof(save_employee_private_details.attrs -> 'address') = 'null' then null else save_employee_private_details.attrs -> 'address' end else x."address" end,
      "emergency_contacts" = case when save_employee_private_details.attrs ? 'emergencyContacts' then coalesce(case when jsonb_typeof(save_employee_private_details.attrs -> 'emergencyContacts') = 'null' then null else save_employee_private_details.attrs -> 'emergencyContacts' end, '[]'::jsonb) else x."emergency_contacts" end,
      "updated_at" = now(),
      "updated_by" = auth.uid()
    where x."employee_id" = v_employee."id"
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a private detail has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_PRIVATE_INVALID';
  end;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

-- An employee's contracts, the newest first. Salaries are minor units as
-- text.
create or replace function "better_supabase"."employee_contracts"(employee uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
begin
  select * into v_employee from "better_supabase"."employees" x where x."id" = employee_contracts.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.view_sensitive'), false) or v_employee."user_id" = auth.uid()) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('salary', x."salary"::text) order by x."starts_on" desc), '[]'::jsonb)
    from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id");
end;
$$;
revoke execute on function "better_supabase"."employee_contracts"(uuid) from public, anon;
grant execute on function "better_supabase"."employee_contracts"(uuid) to authenticated, service_role;

-- Adds a contract: startsOn (required), endsOn, hoursPerWeek, salary
-- (minor units) with currency, salaryPeriod (hour, week, month or year)
-- and note. It starts after the latest contract, which ends the day
-- before. Needs employees.write and employees.view_sensitive.
create or replace function "better_supabase"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.view_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_employee."tenant_id", 'employeeId', v_employee."id", 'subjectType', 'employee', 'subjectId', v_employee."id"::text, 'name', v_employee."name", 'fields', jsonb_build_array('contract')), 'employees/' || v_employee."id"::text, (v_employee."tenant_id"::text)::text, null, 'better-supabase/employees');
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$$;
revoke execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

-- time_entries.employee_id: the employee behind the row's user, kept in step with
-- employees by the two triggers below.
alter table "better_supabase"."time_entries" add column if not exists employee_id uuid references "better_supabase"."employees" ("id") on delete set null;
create index if not exists "time_entries_employee_idx" on "better_supabase"."time_entries" (employee_id) where employee_id is not null;

create or replace function better_supabase.bsb_time_entries_employee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.employee_id := (
    select x."id" from "better_supabase"."employees" x
    where x."tenant_id" = new."tenant_id" and x."user_id" = new."user_id"
  );
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_time_entries_employee() from public, anon, authenticated;
drop trigger if exists bsb_time_entries_employee on "better_supabase"."time_entries";
create trigger bsb_time_entries_employee before insert or update of "user_id" on "better_supabase"."time_entries"
for each row execute function better_supabase.bsb_time_entries_employee();

create or replace function better_supabase.bsb_time_entries_employee_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."user_id" is not null then
    update "better_supabase"."time_entries" set employee_id = null
    where employee_id = old."id" and "user_id" is distinct from new."user_id";
  end if;
  if new."user_id" is not null then
    update "better_supabase"."time_entries" set employee_id = new."id"
    where "tenant_id" = new."tenant_id" and "user_id" = new."user_id"
      and employee_id is distinct from new."id";
  end if;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_time_entries_employee_sync() from public, anon, authenticated;
drop trigger if exists bsb_time_entries_employee_sync on "better_supabase"."employees";
create trigger bsb_time_entries_employee_sync after insert or update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_time_entries_employee_sync();

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."employees";
create policy bsb_tenant_scope on "better_supabase"."employees" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.read')) or "user_id" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."employee_private_details";
create policy bsb_tenant_scope on "better_supabase"."employee_private_details" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.view_sensitive')) or "user_id" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."employee_contracts";
create policy bsb_tenant_scope on "better_supabase"."employee_contracts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('employees.view_sensitive')) or exists (
  select 1 from "better_supabase"."employees" x where x."id" = "employee_id" and x."user_id" = (select auth.uid())))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

drop trigger if exists "bsb_search_employee_index" on "better_supabase"."employees";
create trigger "bsb_search_employee_index"
  after insert or delete or update of "id", "tenant_id", "name", "email", "job_title" on "better_supabase"."employees"
  for each row execute function "better_supabase"."search_index_row"('employee', 'id');

-- blocks.employees.api: entry points for the Data API.
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

create or replace function "api"."create_employee"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_employee"($1, $2) $$;
revoke execute on function "api"."create_employee"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_employee"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_employees"(changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_employees"($1) $$;
revoke execute on function "api"."update_employees"(jsonb) from public, anon;
grant execute on function "api"."update_employees"(jsonb) to authenticated, service_role;

create or replace function "api"."offboard_employee"(employee uuid, end_date date, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."offboard_employee"($1, $2, $3) $$;
revoke execute on function "api"."offboard_employee"(uuid, date, text) from public, anon;
grant execute on function "api"."offboard_employee"(uuid, date, text) to authenticated, service_role;

create or replace function "api"."org_chart"(tenant uuid, root uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."org_chart"($1, $2) $$;
revoke execute on function "api"."org_chart"(uuid, uuid) from public, anon;
grant execute on function "api"."org_chart"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."reports_of"(manager uuid, indirect boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reports_of"($1, $2) $$;
revoke execute on function "api"."reports_of"(uuid, boolean) from public, anon;
grant execute on function "api"."reports_of"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."employee_from_application"(application uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."employee_from_application"($1, $2) $$;
revoke execute on function "api"."employee_from_application"(uuid, jsonb) from public, anon;
grant execute on function "api"."employee_from_application"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."employee_private_details"(employee uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."employee_private_details"($1) $$;
revoke execute on function "api"."employee_private_details"(uuid) from public, anon;
grant execute on function "api"."employee_private_details"(uuid) to authenticated, service_role;

create or replace function "api"."save_employee_private_details"(employee uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_employee_private_details"($1, $2) $$;
revoke execute on function "api"."save_employee_private_details"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_employee_private_details"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."employee_contracts"(employee uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."employee_contracts"($1) $$;
revoke execute on function "api"."employee_contracts"(uuid) from public, anon;
grant execute on function "api"."employee_contracts"(uuid) to authenticated, service_role;

create or replace function "api"."add_employee_contract"(employee uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_employee_contract"($1, $2) $$;
revoke execute on function "api"."add_employee_contract"(uuid, jsonb) from public, anon;
grant execute on function "api"."add_employee_contract"(uuid, jsonb) to authenticated, service_role;

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
