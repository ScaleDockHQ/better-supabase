-- ==== alone: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module onboarding@1 managed
-- Onboarding checklists per user or organization: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
-- Completed onboarding steps, one row per step and subject: a user for a
-- user checklist, an organization for an organization checklist. The
-- checklists live in the app (defineChecklist); the functions check steps
-- against options.checklists.
create table if not exists "better_supabase"."onboarding_progress" (
  "id" uuid primary key default gen_random_uuid(),
  "checklist" text not null,
  "step" text not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "completed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "completed_at" timestamptz not null default now(),
  check (("user_id" is null) <> ("organization_id" is null)),
  unique nulls not distinct ("checklist", "step", "user_id", "organization_id")
);
create index if not exists onboarding_progress_user_idx on "better_supabase"."onboarding_progress" ("user_id");
create index if not exists onboarding_progress_tenant_idx on "better_supabase"."onboarding_progress" ("organization_id");
create index if not exists onboarding_progress_completed_by_idx on "better_supabase"."onboarding_progress" ("completed_by");
alter table "better_supabase"."onboarding_progress" enable row level security;
revoke all on "better_supabase"."onboarding_progress" from anon, authenticated;
grant select on "better_supabase"."onboarding_progress" to authenticated;
grant all on "better_supabase"."onboarding_progress" to service_role;
drop policy if exists "onboarding_progress_read" on "better_supabase"."onboarding_progress";
create policy "onboarding_progress_read" on "better_supabase"."onboarding_progress" for select to authenticated
  using (
    "user_id" = (select auth.uid())
    or "organization_id" in (select better_supabase.tenant_ids_with('onboarding.read'))
  );

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
      'step', x."step",
      'completedAt', x."completed_at",
      'completedBy', x."completed_by"
    ) order by x."completed_at"), '[]'::jsonb)
    from "better_supabase"."onboarding_progress" x
    where x."checklist" = onboarding_progress.checklist
      and (case when v_scope = 'organization' then x."organization_id" = onboarding_progress.tenant else x."user_id" = auth.uid() end)
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
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  insert into "better_supabase"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
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
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  delete from "better_supabase"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function "better_supabase"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('onboarding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module onboarding@1 managed
-- Onboarding checklists per user or organization: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
-- Completed onboarding steps, one row per step and subject: a user for a
-- user checklist, an organization for an organization checklist. The
-- checklists live in the app (defineChecklist); the functions check steps
-- against options.checklists.
create table if not exists "better_supabase"."onboarding_progress" (
  "id" uuid primary key default gen_random_uuid(),
  "checklist" text not null,
  "step" text not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "completed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "completed_at" timestamptz not null default now(),
  check (("user_id" is null) <> ("organization_id" is null)),
  unique nulls not distinct ("checklist", "step", "user_id", "organization_id")
);
create index if not exists onboarding_progress_user_idx on "better_supabase"."onboarding_progress" ("user_id");
create index if not exists onboarding_progress_tenant_idx on "better_supabase"."onboarding_progress" ("organization_id");
create index if not exists onboarding_progress_completed_by_idx on "better_supabase"."onboarding_progress" ("completed_by");
alter table "better_supabase"."onboarding_progress" enable row level security;
revoke all on "better_supabase"."onboarding_progress" from anon, authenticated;
grant select on "better_supabase"."onboarding_progress" to authenticated;
grant all on "better_supabase"."onboarding_progress" to service_role;
drop policy if exists "onboarding_progress_read" on "better_supabase"."onboarding_progress";
create policy "onboarding_progress_read" on "better_supabase"."onboarding_progress" for select to authenticated
  using (
    "user_id" = (select auth.uid())
    or "organization_id" in (select better_supabase.tenant_ids_with('onboarding.read'))
  );

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
      'step', x."step",
      'completedAt', x."completed_at",
      'completedBy', x."completed_by"
    ) order by x."completed_at"), '[]'::jsonb)
    from "better_supabase"."onboarding_progress" x
    where x."checklist" = onboarding_progress.checklist
      and (case when v_scope = 'organization' then x."organization_id" = onboarding_progress.tenant else x."user_id" = auth.uid() end)
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
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  insert into "better_supabase"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
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
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  delete from "better_supabase"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function "better_supabase"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('onboarding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module onboarding@1 managed
-- Onboarding checklists per user or organization: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Completed onboarding steps, one row per step and subject: a user for a
-- user checklist, an organization for an organization checklist. The
-- checklists live in the app (defineChecklist); the functions check steps
-- against options.checklists.
create table if not exists "app_private"."onboarding_progress" (
  "id" uuid primary key default gen_random_uuid(),
  "checklist" text not null,
  "step" text not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "completed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "completed_at" timestamptz not null default now(),
  check (("user_id" is null) <> ("organization_id" is null)),
  unique nulls not distinct ("checklist", "step", "user_id", "organization_id")
);
create index if not exists onboarding_progress_user_idx on "app_private"."onboarding_progress" ("user_id");
create index if not exists onboarding_progress_tenant_idx on "app_private"."onboarding_progress" ("organization_id");
create index if not exists onboarding_progress_completed_by_idx on "app_private"."onboarding_progress" ("completed_by");
alter table "app_private"."onboarding_progress" enable row level security;
revoke all on "app_private"."onboarding_progress" from anon, authenticated;
grant select on "app_private"."onboarding_progress" to authenticated;
grant all on "app_private"."onboarding_progress" to service_role;
drop policy if exists "onboarding_progress_read" on "app_private"."onboarding_progress";
create policy "onboarding_progress_read" on "app_private"."onboarding_progress" for select to authenticated
  using (
    "user_id" = (select auth.uid())
    or "organization_id" in (select better_supabase.tenant_ids_with('onboarding.read'))
  );

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
      'step', x."step",
      'completedAt', x."completed_at",
      'completedBy', x."completed_by"
    ) order by x."completed_at"), '[]'::jsonb)
    from "app_private"."onboarding_progress" x
    where x."checklist" = onboarding_progress.checklist
      and (case when v_scope = 'organization' then x."organization_id" = onboarding_progress.tenant else x."user_id" = auth.uid() end)
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
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  insert into "app_private"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
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
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  delete from "app_private"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke execute on function "app_private"."onboarding_progress"(text, uuid) from public, anon;
revoke execute on function "app_private"."complete_onboarding_step"(text, text, uuid) from public, anon;
revoke execute on function "app_private"."reset_onboarding_step"(text, text, uuid) from public, anon;
grant execute on function "app_private"."onboarding_progress"(text, uuid) to authenticated, service_role;
grant execute on function "app_private"."complete_onboarding_step"(text, text, uuid) to authenticated, service_role;
grant execute on function "app_private"."reset_onboarding_step"(text, text, uuid) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('onboarding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module onboarding@1 managed
-- Onboarding checklists per user or organization: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
-- Completed onboarding steps, one row per step and subject: a user for a
-- user checklist, an organization for an organization checklist. The
-- checklists live in the app (defineChecklist); the functions check steps
-- against options.checklists.
create table if not exists "better_supabase"."onboarding_progress" (
  "id" uuid primary key default gen_random_uuid(),
  "checklist" text not null,
  "step" text not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "completed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "completed_at" timestamptz not null default now(),
  check (("user_id" is null) <> ("organization_id" is null)),
  unique nulls not distinct ("checklist", "step", "user_id", "organization_id")
);
create index if not exists onboarding_progress_user_idx on "better_supabase"."onboarding_progress" ("user_id");
create index if not exists onboarding_progress_tenant_idx on "better_supabase"."onboarding_progress" ("organization_id");
create index if not exists onboarding_progress_completed_by_idx on "better_supabase"."onboarding_progress" ("completed_by");
alter table "better_supabase"."onboarding_progress" enable row level security;
revoke all on "better_supabase"."onboarding_progress" from anon, authenticated;
grant select on "better_supabase"."onboarding_progress" to authenticated;
grant all on "better_supabase"."onboarding_progress" to service_role;
drop policy if exists "onboarding_progress_read" on "better_supabase"."onboarding_progress";
create policy "onboarding_progress_read" on "better_supabase"."onboarding_progress" for select to authenticated
  using (
    "user_id" = (select auth.uid())
    or "organization_id" in (select better_supabase.tenant_ids_with('onboarding.read'))
  );

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
      'step', x."step",
      'completedAt', x."completed_at",
      'completedBy', x."completed_by"
    ) order by x."completed_at"), '[]'::jsonb)
    from "better_supabase"."onboarding_progress" x
    where x."checklist" = onboarding_progress.checklist
      and (case when v_scope = 'organization' then x."organization_id" = onboarding_progress.tenant else x."user_id" = auth.uid() end)
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
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  insert into "better_supabase"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
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
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  delete from "better_supabase"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_37_onboarding.sql
-- better-supabase module: onboarding
-- @bs-module-data onboarding
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('onboarding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
