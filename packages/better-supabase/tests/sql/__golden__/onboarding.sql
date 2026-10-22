-- ==== alone: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block onboarding@2 managed
-- Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Each checklist runs as the enrollment program onboarding:<checklist>: the
-- organization is enrolled in an organization checklist, the user (without a
-- tenant) in a user checklist. The checklists live in the app
-- (defineChecklist); the functions check steps against options.checklists.

-- [{ step, completedAt, completedBy }] of one checklist for the caller, or
-- for tenant when it is an organization checklist (onboarding.read).
create or replace function "better_supabase"."onboarding_progress"(checklist text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = onboarding_progress.checklist and (null::text is null or s.step = null::text) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', onboarding_progress.tenant, 'onboarding.read'), false)) then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', y."step",
      'completedAt', y."completed_at",
      'completedBy', y."completed_by"
    ) order by y."completed_at", array_position(x."steps", y."step")), '[]'::jsonb)
    from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" y on y."enrollment_id" = x."id"
    where x."program" = 'onboarding:' || onboarding_progress.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then onboarding_progress.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then onboarding_progress.tenant::text else auth.uid()::text end)
  );
end;
$$;

-- Marks a step done; false when it already was. Organization steps need
-- onboarding.complete.
create or replace function "better_supabase"."complete_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then complete_onboarding_step.tenant end, 'onboarding:' || complete_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = complete_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then complete_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), complete_onboarding_step.step, true, auth.uid());
end;
$$;

-- Marks a step not done again; false when it wasn't done.
create or replace function "better_supabase"."reset_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
  v_id uuid;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x where x."program" = 'onboarding:' || reset_onboarding_step.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then reset_onboarding_step.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end);
  if v_id is null then
    return false;
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then reset_onboarding_step.tenant end, 'onboarding:' || reset_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = reset_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), reset_onboarding_step.step, false, auth.uid());
end;
$$;

revoke execute on function "better_supabase"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block onboarding@2 managed
-- Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Each checklist runs as the enrollment program onboarding:<checklist>: the
-- organization is enrolled in an organization checklist, the user (without a
-- tenant) in a user checklist. The checklists live in the app
-- (defineChecklist); the functions check steps against options.checklists.

-- [{ step, completedAt, completedBy }] of one checklist for the caller, or
-- for tenant when it is an organization checklist (onboarding.read).
create or replace function "better_supabase"."onboarding_progress"(checklist text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = onboarding_progress.checklist and (null::text is null or s.step = null::text) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', onboarding_progress.tenant, 'onboarding.read'), false)) then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', y."step",
      'completedAt', y."completed_at",
      'completedBy', y."completed_by"
    ) order by y."completed_at", array_position(x."steps", y."step")), '[]'::jsonb)
    from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" y on y."enrollment_id" = x."id"
    where x."program" = 'onboarding:' || onboarding_progress.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then onboarding_progress.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then onboarding_progress.tenant::text else auth.uid()::text end)
  );
end;
$$;

-- Marks a step done; false when it already was. Organization steps need
-- onboarding.complete.
create or replace function "better_supabase"."complete_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then complete_onboarding_step.tenant end, 'onboarding:' || complete_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = complete_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then complete_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), complete_onboarding_step.step, true, auth.uid());
end;
$$;

-- Marks a step not done again; false when it wasn't done.
create or replace function "better_supabase"."reset_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
  v_id uuid;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x where x."program" = 'onboarding:' || reset_onboarding_step.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then reset_onboarding_step.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end);
  if v_id is null then
    return false;
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then reset_onboarding_step.tenant end, 'onboarding:' || reset_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = reset_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), reset_onboarding_step.step, false, auth.uid());
end;
$$;

revoke execute on function "better_supabase"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block onboarding@2 managed
-- Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Each checklist runs as the enrollment program onboarding:<checklist>: the
-- organization is enrolled in an organization checklist, the user (without a
-- tenant) in a user checklist. The checklists live in the app
-- (defineChecklist); the functions check steps against options.checklists.

-- [{ step, completedAt, completedBy }] of one checklist for the caller, or
-- for tenant when it is an organization checklist (onboarding.read).
create or replace function "app_private"."onboarding_progress"(checklist text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = onboarding_progress.checklist and (null::text is null or s.step = null::text) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', onboarding_progress.tenant, 'onboarding.read'), false)) then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', y."step",
      'completedAt', y."completed_at",
      'completedBy', y."completed_by"
    ) order by y."completed_at", array_position(x."steps", y."step")), '[]'::jsonb)
    from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" y on y."enrollment_id" = x."id"
    where x."program" = 'onboarding:' || onboarding_progress.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then onboarding_progress.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then onboarding_progress.tenant::text else auth.uid()::text end)
  );
end;
$$;

-- Marks a step done; false when it already was. Organization steps need
-- onboarding.complete.
create or replace function "app_private"."complete_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then complete_onboarding_step.tenant end, 'onboarding:' || complete_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = complete_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then complete_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), complete_onboarding_step.step, true, auth.uid());
end;
$$;

-- Marks a step not done again; false when it wasn't done.
create or replace function "app_private"."reset_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
  v_id uuid;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x where x."program" = 'onboarding:' || reset_onboarding_step.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then reset_onboarding_step.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end);
  if v_id is null then
    return false;
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then reset_onboarding_step.tenant end, 'onboarding:' || reset_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = reset_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), reset_onboarding_step.step, false, auth.uid());
end;
$$;

revoke execute on function "app_private"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "app_private"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "app_private"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "app_private"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "app_private"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "app_private"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block onboarding@2 managed
-- Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Each checklist runs as the enrollment program onboarding:<checklist>: the
-- organization is enrolled in an organization checklist, the user (without a
-- tenant) in a user checklist. The checklists live in the app
-- (defineChecklist); the functions check steps against options.checklists.

-- [{ step, completedAt, completedBy }] of one checklist for the caller, or
-- for tenant when it is an organization checklist (onboarding.read).
create or replace function "better_supabase"."onboarding_progress"(checklist text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = onboarding_progress.checklist and (null::text is null or s.step = null::text) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding checklist %', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if onboarding_progress.tenant is null then
      raise exception 'Checklist % belongs to an organization', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', onboarding_progress.tenant, 'onboarding.read'), false)) then
      raise exception 'You may not see this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
    end if;
  elsif onboarding_progress.tenant is not null then
    raise exception 'Checklist % belongs to a user', onboarding_progress.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'step', y."step",
      'completedAt', y."completed_at",
      'completedBy', y."completed_by"
    ) order by y."completed_at", array_position(x."steps", y."step")), '[]'::jsonb)
    from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" y on y."enrollment_id" = x."id"
    where x."program" = 'onboarding:' || onboarding_progress.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then onboarding_progress.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then onboarding_progress.tenant::text else auth.uid()::text end)
  );
end;
$$;

-- Marks a step done; false when it already was. Organization steps need
-- onboarding.complete.
create or replace function "better_supabase"."complete_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then complete_onboarding_step.tenant end, 'onboarding:' || complete_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = complete_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then complete_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), complete_onboarding_step.step, true, auth.uid());
end;
$$;

-- Marks a step not done again; false when it wasn't done.
create or replace function "better_supabase"."reset_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text;
  v_id uuid;
begin
  v_scope := (select s.scope from (select null::text as checklist, null::text as step, null::text as scope where false) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x where x."program" = 'onboarding:' || reset_onboarding_step.checklist
    and x."tenant_id" is not distinct from (case when v_scope = 'organization' then reset_onboarding_step.tenant end)
    and x."subject_type" = v_scope
    and x."subject_id" = (case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end);
  if v_id is null then
    return false;
  end if;
  return "better_supabase"."enrollment_mark"("better_supabase"."enrollment_ensure"(case when v_scope = 'organization' then reset_onboarding_step.tenant end, 'onboarding:' || reset_onboarding_step.checklist, null, (select c.steps from (select null::text as checklist, null::text as scope, null::text[] as steps where false) as c(checklist, scope, steps) where c.checklist = reset_onboarding_step.checklist), v_scope, case when v_scope = 'organization' then reset_onboarding_step.tenant::text else auth.uid()::text end, auth.uid()), reset_onboarding_step.step, false, auth.uid());
end;
$$;

revoke execute on function "better_supabase"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

-- blocks.onboarding.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."onboarding_progress"(checklist text, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."onboarding_progress"($1, $2) $$;
revoke execute on function "api"."onboarding_progress"(text, uuid) from public, anon;
grant execute on function "api"."onboarding_progress"(text, uuid) to authenticated, service_role;

create or replace function "api"."complete_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_onboarding_step"($1, $2, $3) $$;
revoke execute on function "api"."complete_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "api"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;

create or replace function "api"."reset_onboarding_step"(checklist text, step text, tenant uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reset_onboarding_step"($1, $2, $3) $$;
revoke execute on function "api"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "api"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
