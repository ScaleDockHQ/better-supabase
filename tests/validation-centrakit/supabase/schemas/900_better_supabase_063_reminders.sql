-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:22b14b9f2a9209c19c22cdc2ad9f59cd96a13dbc1338c8e5e73e9b412d719285
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
    drop policy if exists bsb_tenant_scope on "centrakit"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."recurrence_rules";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."recurrence_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "centrakit"."reminders";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."reminders";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."reminders";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."reminders";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."reminders";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- centrakit.recurrence_rules is the app's table, and it has every column this block needs.
alter table "centrakit"."recurrence_rules" enable row level security;
grant select on "centrakit"."recurrence_rules" to authenticated;
grant all on "centrakit"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "centrakit"."recurrence_rules" ("subject_type", "subject_id");
-- centrakit.reminders is the app's table, and it has every column this block needs.
alter table "centrakit"."reminders" add column if not exists "remind_at" timestamptz;
alter table "centrakit"."reminders" enable row level security;
grant select on "centrakit"."reminders" to authenticated;
grant all on "centrakit"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "centrakit"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "centrakit"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"centrakit"."reminders"'::regclass and conname = 'reminders_offset_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"centrakit"."reminders"', 'reminders_offset_check', '"centrakit"."reminders"', 'reminders_offset_check';
    end;
  end if;
end;
$$;
-- centrakit.reminder_deliveries is the app's table, and it has every column this block needs.
alter table "centrakit"."reminder_deliveries" enable row level security;
grant select on "centrakit"."reminder_deliveries" to authenticated;
grant all on "centrakit"."reminder_deliveries" to service_role;

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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  if not (auth.role() = 'service_role')
    and save_reminder.subject_type in ('message', 'conversation', 'task', 'project', 'customer')
    and not (case save_reminder.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'comments.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'comments.read'), false)
    when 'task' then exists (select 1 from "centrakit"."tasks" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant)
    when 'project' then exists (select 1 from "centrakit"."projects" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant)
    when 'customer' then exists (select 1 from "centrakit"."customers" s where s."id" = (save_reminder.subject_id)::bigint and s."organization_id" = save_reminder.tenant)
    else false
  end) then
    raise exception 'the record was not found in this organization' using errcode = 'P0002', hint = 'REMINDER_SUBJECT_NOT_FOUND';
  end if;
  insert into "centrakit"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
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
    from "centrakit"."reminders" r
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "centrakit"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "centrakit"."reminders" r where r."id" = delete_reminder.reminder;
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
    from "centrakit"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "centrakit"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('reminder.sent', jsonb_build_object('organizationId', v_tenant, 'id', mark_reminder_sent.reminder, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'userId', v_user), 'reminders/' || mark_reminder_sent.reminder::text, (v_tenant)::text, null, 'domain');
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
  from "centrakit"."reminders" r
  join "centrakit"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "centrakit"."reminders" r
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
drop policy if exists bsb_tenant_scope on "centrakit"."recurrence_rules";
drop policy if exists bsb_tenant_scope_select on "centrakit"."recurrence_rules";
create policy bsb_tenant_scope_select on "centrakit"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "centrakit"."recurrence_rules";
create policy bsb_tenant_scope_insert on "centrakit"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "centrakit"."recurrence_rules";
create policy bsb_tenant_scope_update on "centrakit"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "centrakit"."recurrence_rules";
create policy bsb_tenant_scope_delete on "centrakit"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "centrakit"."reminders";
drop policy if exists bsb_tenant_scope_select on "centrakit"."reminders";
create policy bsb_tenant_scope_select on "centrakit"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "centrakit"."reminders";
create policy bsb_tenant_scope_insert on "centrakit"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "centrakit"."reminders";
create policy bsb_tenant_scope_update on "centrakit"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "centrakit"."reminders";
create policy bsb_tenant_scope_delete on "centrakit"."reminders" as restrictive
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
