-- ==== alone: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:bf40715ae960153b194cdc1a0d471ae8c542d91bff461147f85cc86287a85e10
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."recurrence_rules" enable row level security;
revoke all on "better_supabase"."recurrence_rules" from public, anon, authenticated;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
create table if not exists "better_supabase"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
revoke all on "better_supabase"."reminders" from public, anon, authenticated;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "better_supabase"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    alter table "better_supabase"."reminders" add constraint "reminders_offset_check"
      check ("offset_minutes" between -525600 and 525600) not valid;
    begin
      alter table "better_supabase"."reminders" validate constraint "reminders_offset_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."reminders"', 'reminders_offset_check', '"better_supabase"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
create table if not exists "better_supabase"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "better_supabase"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "better_supabase"."reminder_deliveries" enable row level security;
revoke all on "better_supabase"."reminder_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;

drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "better_supabase"."list_reminder_schedule"();
create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:b2e4a757d5afa6edae53cdd6165c40c422900a1ca84863ebe6045d5b9525af1e
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."recurrence_rules" enable row level security;
revoke all on "better_supabase"."recurrence_rules" from public, anon, authenticated;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
create table if not exists "better_supabase"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
revoke all on "better_supabase"."reminders" from public, anon, authenticated;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "better_supabase"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    alter table "better_supabase"."reminders" add constraint "reminders_offset_check"
      check ("offset_minutes" between -525600 and 525600) not valid;
    begin
      alter table "better_supabase"."reminders" validate constraint "reminders_offset_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."reminders"', 'reminders_offset_check', '"better_supabase"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
create table if not exists "better_supabase"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "better_supabase"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "better_supabase"."reminder_deliveries" enable row level security;
revoke all on "better_supabase"."reminder_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;

drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('reminder.sent', jsonb_build_object('organizationId', v_tenant, 'id', mark_reminder_sent.reminder, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'userId', v_user), 'reminders/' || mark_reminder_sent.reminder::text, (v_tenant)::text, null, 'better-supabase/reminders');
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "better_supabase"."list_reminder_schedule"();
create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.reminders', target_type => 'reminder', event_prefix => 'reminder', deferred => true);
end;
$$;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:7e337ee5de0c7c221fa4c045a5aa003935710f8a38c73e5ef2766a90b8d06028
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "app_private"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "app_private"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "app_private"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."reminders";
    drop policy if exists bsb_tenant_scope_select on "app_private"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."reminders";
    drop policy if exists bsb_tenant_scope_update on "app_private"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."reminders";
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
create table if not exists "app_private"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("tenant_id", "subject_type", "subject_id")
);
alter table "app_private"."recurrence_rules" enable row level security;
revoke all on "app_private"."recurrence_rules" from public, anon, authenticated;
grant select on "app_private"."recurrence_rules" to authenticated;
grant all on "app_private"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "app_private"."recurrence_rules" ("subject_type", "subject_id");
create table if not exists "app_private"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "app_private"."reminders" add column if not exists "remind_at" timestamptz;
alter table "app_private"."reminders" enable row level security;
revoke all on "app_private"."reminders" from public, anon, authenticated;
grant select on "app_private"."reminders" to authenticated;
grant all on "app_private"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "app_private"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "app_private"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"app_private"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    alter table "app_private"."reminders" add constraint "reminders_offset_check"
      check ("offset_minutes" between -525600 and 525600) not valid;
    begin
      alter table "app_private"."reminders" validate constraint "reminders_offset_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"app_private"."reminders"', 'reminders_offset_check', '"app_private"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
create table if not exists "app_private"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "app_private"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "app_private"."reminder_deliveries" enable row level security;
revoke all on "app_private"."reminder_deliveries" from public, anon, authenticated;
grant select on "app_private"."reminder_deliveries" to authenticated;
grant all on "app_private"."reminder_deliveries" to service_role;

drop function if exists "app_private"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "app_private"."save_reminder"(uuid, text, text, integer);
drop function if exists "app_private"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "app_private"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "app_private"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "app_private"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "app_private"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "app_private"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "app_private"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "app_private"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "app_private"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "app_private"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "app_private"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_reminder"(uuid) from public, anon;
grant execute on function "app_private"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "app_private"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "app_private"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "app_private"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "app_private"."list_reminder_schedule"();
create function "app_private"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "app_private"."reminders" r
  join "app_private"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "app_private"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "app_private"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "app_private"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "app_private"."recurrence_rules";
create policy bsb_tenant_scope_select on "app_private"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."recurrence_rules";
create policy bsb_tenant_scope_insert on "app_private"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."recurrence_rules";
create policy bsb_tenant_scope_update on "app_private"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."recurrence_rules";
create policy bsb_tenant_scope_delete on "app_private"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."reminders";
drop policy if exists bsb_tenant_scope_select on "app_private"."reminders";
create policy bsb_tenant_scope_select on "app_private"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."reminders";
create policy bsb_tenant_scope_insert on "app_private"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."reminders";
create policy bsb_tenant_scope_update on "app_private"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."reminders";
create policy bsb_tenant_scope_delete on "app_private"."reminders" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:526a4af217c3f3b384a423bf3b0bd5bf37bc325d950c97b338365fcf929b525b
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."recurrence_rules" enable row level security;
revoke all on "better_supabase"."recurrence_rules" from public, anon, authenticated;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
create table if not exists "better_supabase"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
revoke all on "better_supabase"."reminders" from public, anon, authenticated;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "better_supabase"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    alter table "better_supabase"."reminders" add constraint "reminders_offset_check"
      check ("offset_minutes" between -525600 and 525600) not valid;
    begin
      alter table "better_supabase"."reminders" validate constraint "reminders_offset_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."reminders"', 'reminders_offset_check', '"better_supabase"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
create table if not exists "better_supabase"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "better_supabase"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "better_supabase"."reminder_deliveries" enable row level security;
revoke all on "better_supabase"."reminder_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;

drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "better_supabase"."list_reminder_schedule"();
create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.reminders.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "api"."save_reminder"(uuid, text, text, integer);
drop function if exists "api"."save_reminder"(uuid, text, text, integer, jsonb);
drop function if exists "api"."list_reminder_schedule"();

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

create or replace function "api"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_reminder"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "api"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_my_reminders"($1, $2, $3) $$;
revoke execute on function "api"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "api"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."delete_reminder"(reminder uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_reminder"($1) $$;
revoke execute on function "api"."delete_reminder"(uuid) from public, anon;
grant execute on function "api"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "api"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_reminder_sent"($1, $2) $$;
revoke execute on function "api"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "api"."mark_reminder_sent"(uuid, timestamptz) to service_role;

create or replace function "api"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_reminder_schedule"() $$;
revoke execute on function "api"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "api"."list_reminder_schedule"() to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:3c60930828da780d3c3a9f4b4e5f22fc9ee8cd5dd4d891a36c8e4935f5a02097
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.recurrence_rules is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."recurrence_rules" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."recurrence_rules" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."recurrence_rules" add column if not exists "subject_type" text;
alter table "better_supabase"."recurrence_rules" add column if not exists "subject_id" text;
alter table "better_supabase"."recurrence_rules" add column if not exists "dtstart" timestamptz;
alter table "better_supabase"."recurrence_rules" add column if not exists "tzid" text not null default 'UTC';
alter table "better_supabase"."recurrence_rules" add column if not exists "rrule" text;
alter table "better_supabase"."recurrence_rules" enable row level security;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
-- better_supabase.reminders is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."reminders" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."reminders" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."reminders" add column if not exists "subject_type" text;
alter table "better_supabase"."reminders" add column if not exists "subject_id" text;
alter table "better_supabase"."reminders" add column if not exists "user_id" uuid;
alter table "better_supabase"."reminders" add column if not exists "method" text not null default 'notification';
alter table "better_supabase"."reminders" add column if not exists "offset_minutes" integer not null default 0;
alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "better_supabase"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."reminders"', 'reminders_offset_check', '"better_supabase"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
-- better_supabase.reminder_deliveries is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."reminder_deliveries" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."reminder_deliveries" add column if not exists "reminder_id" uuid references "better_supabase"."reminders" ("id") on delete cascade;
alter table "better_supabase"."reminder_deliveries" add column if not exists "occurrence_at" timestamptz;
alter table "better_supabase"."reminder_deliveries" add column if not exists "sent_at" timestamptz;
alter table "better_supabase"."reminder_deliveries" enable row level security;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;

drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "better_supabase"."list_reminder_schedule"();
create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:a82840b29fdfdae884c0b51424c9760fd2ea090c4091ed1bedeb43ceee328307
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("org_id", "subject_type", "subject_id")
);
alter table "better_supabase"."recurrence_rules" enable row level security;
revoke all on "better_supabase"."recurrence_rules" from public, anon, authenticated;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
create table if not exists "better_supabase"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
revoke all on "better_supabase"."reminders" from public, anon, authenticated;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "better_supabase"."reminders" ("org_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    alter table "better_supabase"."reminders" add constraint "reminders_offset_check"
      check ("offset_minutes" between -525600 and 525600) not valid;
    begin
      alter table "better_supabase"."reminders" validate constraint "reminders_offset_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."reminders"', 'reminders_offset_check', '"better_supabase"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
create table if not exists "better_supabase"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "better_supabase"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "better_supabase"."reminder_deliveries" enable row level security;
revoke all on "better_supabase"."reminder_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;

drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz, jsonb);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);
drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer, jsonb);
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("org_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."org_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."org_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "org_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).
drop function if exists "better_supabase"."list_reminder_schedule"();
create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."org_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."org_id" = r."org_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."org_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."recurrence_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."reminders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reminders";
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reminders";
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reminders";
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reminders";
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
