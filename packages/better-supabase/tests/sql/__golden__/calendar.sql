-- ==== alone: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:258c6cf6455b0c4b08e3b0c18d5dfc078f213e82f4ad8962c6463c8f4556ad68
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."calendars" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "tz" text not null default 'UTC',
  "color" text,
  "owner_type" text,
  "owner_id" text,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."calendars" enable row level security;
revoke all on "better_supabase"."calendars" from public, anon, authenticated;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "better_supabase"."calendars" ("tenant_id");
drop policy if exists calendars_read on "better_supabase"."calendars";
create policy calendars_read on "better_supabase"."calendars"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "calendar_id" uuid not null references "better_supabase"."calendars" ("id") on delete cascade,
  "uid" text not null,
  "title" text not null default '',
  "description" text,
  "location" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "all_day" boolean not null default false,
  "tz" text not null default 'UTC',
  "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled')),
  "rrule" text,
  "exdates" timestamptz[] not null default '{}',
  "recurrence_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade,
  "original_start" timestamptz,
  "subject_type" text,
  "subject_id" text,
  "color" text,
  "kind" text not null default 'event',
  "transparency" text not null default 'opaque',
  "auto_decline" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_kind_check"
      check ("kind" in ('event', 'out_of_office', 'focus_time')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_kind_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_kind_check', '"better_supabase"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_transparency_check"
      check ("transparency" in ('opaque', 'transparent')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_transparency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_transparency_check', '"better_supabase"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."calendar_events" enable row level security;
revoke all on "better_supabase"."calendar_events" from public, anon, authenticated;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "better_supabase"."calendar_events";
create policy calendar_events_read on "better_supabase"."calendar_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_attendees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "event_id" uuid not null references "better_supabase"."calendar_events" ("id") on delete cascade,
  "email" text not null,
  "name" text,
  "user_id" uuid,
  "role" text not null default 'required',
  "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative')),
  unique ("event_id", "email")
);
alter table "better_supabase"."calendar_attendees" enable row level security;
revoke all on "better_supabase"."calendar_attendees" from public, anon, authenticated;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    alter table "better_supabase"."calendar_attendees" add constraint "calendar_attendees_role_check"
      check ("role" in ('chair', 'required', 'optional', 'non-participant')) not valid;
    begin
      alter table "better_supabase"."calendar_attendees" validate constraint "calendar_attendees_role_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check', '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists calendar_attendees_read on "better_supabase"."calendar_attendees";
create policy calendar_attendees_read on "better_supabase"."calendar_attendees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
create table if not exists "better_supabase"."calendar_working_hours" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  "tz" text not null default 'UTC',
  check ("ends_at" > "starts_at"),
  unique ("tenant_id", "user_id", "weekday", "starts_at")
);
alter table "better_supabase"."calendar_working_hours" enable row level security;
revoke all on "better_supabase"."calendar_working_hours" from public, anon, authenticated;
grant select on "better_supabase"."calendar_working_hours" to authenticated;
grant all on "better_supabase"."calendar_working_hours" to service_role;
drop policy if exists calendar_working_hours_read on "better_supabase"."calendar_working_hours";
create policy calendar_working_hours_read on "better_supabase"."calendar_working_hours"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "better_supabase"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "better_supabase"."calendars" ("tenant_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "better_supabase"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "better_supabase"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "better_supabase"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  null;
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "better_supabase"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "better_supabase"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "better_supabase"."calendars" k
  where k."tenant_id" = list_calendars.tenant
$$;
revoke execute on function "better_supabase"."list_calendars"(uuid) from public, anon;
grant execute on function "better_supabase"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "better_supabase"."calendar_attendees" ("tenant_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "better_supabase"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "better_supabase"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "better_supabase"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$$;
revoke execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "better_supabase"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "better_supabase"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "better_supabase"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_attendees_auto_decline" on "better_supabase"."calendar_attendees";
create trigger "calendar_attendees_auto_decline"
before insert or update of "user_id" on "better_supabase"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "better_supabase"."calendar_attendee_auto_decline"();

create or replace function "better_supabase"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "better_supabase"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_events_auto_decline" on "better_supabase"."calendar_events";
create trigger "calendar_events_auto_decline"
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "better_supabase"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "better_supabase"."calendar_block_auto_decline"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
create policy bsb_tenant_scope_select on "better_supabase"."calendars" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
create policy bsb_tenant_scope_insert on "better_supabase"."calendars" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
create policy bsb_tenant_scope_update on "better_supabase"."calendars" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
create policy bsb_tenant_scope_delete on "better_supabase"."calendars" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_working_hours" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_working_hours" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:df953698cf959af409205423f1a45626fda3ebfebda00625d56037b3a5e788c5
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."calendars" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "tz" text not null default 'UTC',
  "color" text,
  "owner_type" text,
  "owner_id" text,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."calendars" enable row level security;
revoke all on "better_supabase"."calendars" from public, anon, authenticated;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "better_supabase"."calendars" ("tenant_id");
drop policy if exists calendars_read on "better_supabase"."calendars";
create policy calendars_read on "better_supabase"."calendars"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "calendar_id" uuid not null references "better_supabase"."calendars" ("id") on delete cascade,
  "uid" text not null,
  "title" text not null default '',
  "description" text,
  "location" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "all_day" boolean not null default false,
  "tz" text not null default 'UTC',
  "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled')),
  "rrule" text,
  "exdates" timestamptz[] not null default '{}',
  "recurrence_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade,
  "original_start" timestamptz,
  "subject_type" text,
  "subject_id" text,
  "color" text,
  "kind" text not null default 'event',
  "transparency" text not null default 'opaque',
  "auto_decline" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_kind_check"
      check ("kind" in ('event', 'out_of_office', 'focus_time')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_kind_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_kind_check', '"better_supabase"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_transparency_check"
      check ("transparency" in ('opaque', 'transparent')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_transparency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_transparency_check', '"better_supabase"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."calendar_events" enable row level security;
revoke all on "better_supabase"."calendar_events" from public, anon, authenticated;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "better_supabase"."calendar_events";
create policy calendar_events_read on "better_supabase"."calendar_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_attendees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "event_id" uuid not null references "better_supabase"."calendar_events" ("id") on delete cascade,
  "email" text not null,
  "name" text,
  "user_id" uuid,
  "role" text not null default 'required',
  "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative')),
  unique ("event_id", "email")
);
alter table "better_supabase"."calendar_attendees" enable row level security;
revoke all on "better_supabase"."calendar_attendees" from public, anon, authenticated;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    alter table "better_supabase"."calendar_attendees" add constraint "calendar_attendees_role_check"
      check ("role" in ('chair', 'required', 'optional', 'non-participant')) not valid;
    begin
      alter table "better_supabase"."calendar_attendees" validate constraint "calendar_attendees_role_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check', '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists calendar_attendees_read on "better_supabase"."calendar_attendees";
create policy calendar_attendees_read on "better_supabase"."calendar_attendees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
create table if not exists "better_supabase"."calendar_working_hours" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  "tz" text not null default 'UTC',
  check ("ends_at" > "starts_at"),
  unique ("tenant_id", "user_id", "weekday", "starts_at")
);
alter table "better_supabase"."calendar_working_hours" enable row level security;
revoke all on "better_supabase"."calendar_working_hours" from public, anon, authenticated;
grant select on "better_supabase"."calendar_working_hours" to authenticated;
grant all on "better_supabase"."calendar_working_hours" to service_role;
drop policy if exists calendar_working_hours_read on "better_supabase"."calendar_working_hours";
create policy calendar_working_hours_read on "better_supabase"."calendar_working_hours"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "better_supabase"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "better_supabase"."calendars" ("tenant_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  perform "better_supabase".emit_event('calendar.created', jsonb_build_object('organizationId', create_calendar.tenant, 'id', v_id, 'name', create_calendar.name), 'calendars/' || v_id::text, (create_calendar.tenant)::text, null, 'better-supabase/calendar');
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "better_supabase"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  if v_created then
    perform "better_supabase".emit_event('calendar_event.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  else
    perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'calendar_event' and "subject_id" = v_id::text;
  perform "better_supabase".emit_event('calendar_event.deleted', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "better_supabase"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "better_supabase"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', v_calendar), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "better_supabase"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "better_supabase"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "better_supabase"."calendars" k
  where k."tenant_id" = list_calendars.tenant
$$;
revoke execute on function "better_supabase"."list_calendars"(uuid) from public, anon;
grant execute on function "better_supabase"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "better_supabase"."calendar_attendees" ("tenant_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "better_supabase"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "better_supabase"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "better_supabase"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    )
  union all
  select r."user_id", 'out_of_office'::text, t.s, t.en, null::uuid, true
  from "better_supabase"."leave_requests" r
  cross join lateral (select coalesce((select h."tz" from "better_supabase"."calendar_working_hours" h where h."tenant_id" = calendar_busy_blocks.tenant and h."user_id" = r."user_id" limit 1), 'UTC') as tz) z
  cross join lateral (
    select
      (case when r."partial" = 'afternoon' then r."starts_on" + time '12:00' else r."starts_on"::timestamp end) at time zone z.tz as s,
      (case r."partial" when 'morning' then r."starts_on" + time '12:00' when 'afternoon' then (r."starts_on" + 1)::timestamp else (r."ends_on" + 1)::timestamp end) at time zone z.tz as en
  ) t
  where r."tenant_id" = calendar_busy_blocks.tenant
    and r."user_id" = any (calendar_busy_blocks.user_ids)
    and r."approved_at" is not null
    and r."cancelled_at" is null
    and r."partial" <> 'hours'
    and t.s < calendar_busy_blocks.range_end
    and t.en > calendar_busy_blocks.range_start;
end;
$$;
revoke execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "better_supabase"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "better_supabase"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "better_supabase"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_attendees_auto_decline" on "better_supabase"."calendar_attendees";
create trigger "calendar_attendees_auto_decline"
before insert or update of "user_id" on "better_supabase"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "better_supabase"."calendar_attendee_auto_decline"();

create or replace function "better_supabase"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "better_supabase"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_events_auto_decline" on "better_supabase"."calendar_events";
create trigger "calendar_events_auto_decline"
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "better_supabase"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "better_supabase"."calendar_block_auto_decline"();

-- The events of the calendar a share link points at, for an iCal feed. Open
-- to anon: the token is the credential, and it is hashed before the lookup.
create or replace function "better_supabase"."calendar_feed"(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_subject text;
  v_tenant text;
  v_calendar uuid;
begin
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text into v_subject, v_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(calendar_feed.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'calendar'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz"),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at")
        from "better_supabase"."calendar_events" e
        where e."calendar_id" = v_calendar
          and (e."rrule" is not null or e."ends_at" > now() - interval '1 year')
      ), '[]'::jsonb)
    )
    from "better_supabase"."calendars" k where k."id" = v_calendar and k."tenant_id"::text = v_tenant
  );
end;
$$;
revoke all on function "better_supabase"."calendar_feed"(text) from public;
grant execute on function "better_supabase"."calendar_feed"(text) to anon, authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
create policy bsb_tenant_scope_select on "better_supabase"."calendars" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
create policy bsb_tenant_scope_insert on "better_supabase"."calendars" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
create policy bsb_tenant_scope_update on "better_supabase"."calendars" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
create policy bsb_tenant_scope_delete on "better_supabase"."calendars" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_working_hours" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_working_hours" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:887f61d1d8d8842f7573a7dfeea4d1bd5a7298d8fb582e7d9caa5b6ff06c7b26
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
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
    drop policy if exists bsb_tenant_scope on "app_private"."calendars";
    drop policy if exists bsb_tenant_scope_select on "app_private"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."calendars";
    drop policy if exists bsb_tenant_scope_update on "app_private"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_working_hours";
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
create table if not exists "app_private"."calendars" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "tz" text not null default 'UTC',
  "color" text,
  "owner_type" text,
  "owner_id" text,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."calendars" enable row level security;
revoke all on "app_private"."calendars" from public, anon, authenticated;
grant select on "app_private"."calendars" to authenticated;
grant all on "app_private"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "app_private"."calendars" ("tenant_id");
drop policy if exists calendars_read on "app_private"."calendars";
create policy calendars_read on "app_private"."calendars"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "app_private"."calendar_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "calendar_id" uuid not null references "app_private"."calendars" ("id") on delete cascade,
  "uid" text not null,
  "title" text not null default '',
  "description" text,
  "location" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "all_day" boolean not null default false,
  "tz" text not null default 'UTC',
  "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled')),
  "rrule" text,
  "exdates" timestamptz[] not null default '{}',
  "recurrence_id" uuid references "app_private"."calendar_events" ("id") on delete cascade,
  "original_start" timestamptz,
  "subject_type" text,
  "subject_id" text,
  "color" text,
  "kind" text not null default 'event',
  "transparency" text not null default 'opaque',
  "auto_decline" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "app_private"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "app_private"."calendar_events" ("calendar_id", "starts_at");
alter table "app_private"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "app_private"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "app_private"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"app_private"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    alter table "app_private"."calendar_events" add constraint "calendar_events_kind_check"
      check ("kind" in ('event', 'out_of_office', 'focus_time')) not valid;
    begin
      alter table "app_private"."calendar_events" validate constraint "calendar_events_kind_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"app_private"."calendar_events"', 'calendar_events_kind_check', '"app_private"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"app_private"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    alter table "app_private"."calendar_events" add constraint "calendar_events_transparency_check"
      check ("transparency" in ('opaque', 'transparent')) not valid;
    begin
      alter table "app_private"."calendar_events" validate constraint "calendar_events_transparency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"app_private"."calendar_events"', 'calendar_events_transparency_check', '"app_private"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "app_private"."calendar_events" enable row level security;
revoke all on "app_private"."calendar_events" from public, anon, authenticated;
grant select on "app_private"."calendar_events" to authenticated;
grant all on "app_private"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "app_private"."calendar_events";
create policy calendar_events_read on "app_private"."calendar_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "app_private"."calendar_attendees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "event_id" uuid not null references "app_private"."calendar_events" ("id") on delete cascade,
  "email" text not null,
  "name" text,
  "user_id" uuid,
  "role" text not null default 'required',
  "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative')),
  unique ("event_id", "email")
);
alter table "app_private"."calendar_attendees" enable row level security;
revoke all on "app_private"."calendar_attendees" from public, anon, authenticated;
grant select on "app_private"."calendar_attendees" to authenticated;
grant all on "app_private"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"app_private"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    alter table "app_private"."calendar_attendees" add constraint "calendar_attendees_role_check"
      check ("role" in ('chair', 'required', 'optional', 'non-participant')) not valid;
    begin
      alter table "app_private"."calendar_attendees" validate constraint "calendar_attendees_role_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"app_private"."calendar_attendees"', 'calendar_attendees_role_check', '"app_private"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists calendar_attendees_read on "app_private"."calendar_attendees";
create policy calendar_attendees_read on "app_private"."calendar_attendees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
create table if not exists "app_private"."calendar_working_hours" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  "tz" text not null default 'UTC',
  check ("ends_at" > "starts_at"),
  unique ("tenant_id", "user_id", "weekday", "starts_at")
);
alter table "app_private"."calendar_working_hours" enable row level security;
revoke all on "app_private"."calendar_working_hours" from public, anon, authenticated;
grant select on "app_private"."calendar_working_hours" to authenticated;
grant all on "app_private"."calendar_working_hours" to service_role;
drop policy if exists calendar_working_hours_read on "app_private"."calendar_working_hours";
create policy calendar_working_hours_read on "app_private"."calendar_working_hours"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "app_private"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "app_private"."calendars" ("tenant_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "app_private"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "app_private"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "app_private"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_calendar"(uuid) from public, anon;
grant execute on function "app_private"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "app_private"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "app_private"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "app_private"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "app_private"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "app_private"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "app_private"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "app_private"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "app_private"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "app_private"."calendar_events" where "id" = v_id;
  
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "app_private"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "app_private"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "app_private"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "app_private"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "app_private"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "app_private"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "app_private"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "app_private"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "app_private"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  
  v_new := "app_private"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "app_private"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  null;
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "app_private"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "app_private"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "app_private"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "app_private"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "app_private"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "app_private"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "app_private"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "app_private"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "app_private"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "app_private"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "app_private"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "app_private"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "app_private"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "app_private"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "app_private"."calendars" k
  where k."tenant_id" = list_calendars.tenant
$$;
revoke execute on function "app_private"."list_calendars"(uuid) from public, anon;
grant execute on function "app_private"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "app_private"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "tenant_id" into v_tenant from "app_private"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "app_private"."calendar_attendees" ("tenant_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "app_private"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "app_private"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "app_private"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "app_private"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "app_private"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "app_private"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "app_private"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "app_private"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "app_private"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "app_private"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "app_private"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "app_private"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "app_private"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "app_private"."calendar_attendees" a
    join "app_private"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "app_private"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "app_private"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "app_private"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "app_private"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$$;
revoke execute on function "app_private"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "app_private"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "app_private"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "app_private"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "app_private"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "app_private"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "app_private"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "app_private"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "app_private"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "app_private"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "app_private"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "app_private"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "app_private"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "app_private"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "app_private"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "app_private"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_attendees_auto_decline" on "app_private"."calendar_attendees";
create trigger "calendar_attendees_auto_decline"
before insert or update of "user_id" on "app_private"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "app_private"."calendar_attendee_auto_decline"();

create or replace function "app_private"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "app_private"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "app_private"."calendar_attendees" a set "response" = 'declined'
  from "app_private"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "app_private"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_events_auto_decline" on "app_private"."calendar_events";
create trigger "calendar_events_auto_decline"
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "app_private"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "app_private"."calendar_block_auto_decline"();

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
drop policy if exists bsb_tenant_scope on "app_private"."calendars";
drop policy if exists bsb_tenant_scope_select on "app_private"."calendars";
create policy bsb_tenant_scope_select on "app_private"."calendars" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."calendars";
create policy bsb_tenant_scope_insert on "app_private"."calendars" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."calendars";
create policy bsb_tenant_scope_update on "app_private"."calendars" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."calendars";
create policy bsb_tenant_scope_delete on "app_private"."calendars" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_events";
create policy bsb_tenant_scope_select on "app_private"."calendar_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_events";
create policy bsb_tenant_scope_insert on "app_private"."calendar_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_events";
create policy bsb_tenant_scope_update on "app_private"."calendar_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_events";
create policy bsb_tenant_scope_delete on "app_private"."calendar_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_attendees";
create policy bsb_tenant_scope_select on "app_private"."calendar_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_attendees";
create policy bsb_tenant_scope_insert on "app_private"."calendar_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_attendees";
create policy bsb_tenant_scope_update on "app_private"."calendar_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_attendees";
create policy bsb_tenant_scope_delete on "app_private"."calendar_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "app_private"."calendar_working_hours";
create policy bsb_tenant_scope_select on "app_private"."calendar_working_hours" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "app_private"."calendar_working_hours" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."calendar_working_hours";
create policy bsb_tenant_scope_update on "app_private"."calendar_working_hours" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "app_private"."calendar_working_hours" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:c61aea241cee5ba2a5631218278755a0a46e948e35f63bb712259d9da759d813
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."calendars" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "tz" text not null default 'UTC',
  "color" text,
  "owner_type" text,
  "owner_id" text,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."calendars" enable row level security;
revoke all on "better_supabase"."calendars" from public, anon, authenticated;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "better_supabase"."calendars" ("tenant_id");
drop policy if exists calendars_read on "better_supabase"."calendars";
create policy calendars_read on "better_supabase"."calendars"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "calendar_id" uuid not null references "better_supabase"."calendars" ("id") on delete cascade,
  "uid" text not null,
  "title" text not null default '',
  "description" text,
  "location" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "all_day" boolean not null default false,
  "tz" text not null default 'UTC',
  "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled')),
  "rrule" text,
  "exdates" timestamptz[] not null default '{}',
  "recurrence_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade,
  "original_start" timestamptz,
  "subject_type" text,
  "subject_id" text,
  "color" text,
  "kind" text not null default 'event',
  "transparency" text not null default 'opaque',
  "auto_decline" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_kind_check"
      check ("kind" in ('event', 'out_of_office', 'focus_time')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_kind_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_kind_check', '"better_supabase"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_transparency_check"
      check ("transparency" in ('opaque', 'transparent')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_transparency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_transparency_check', '"better_supabase"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."calendar_events" enable row level security;
revoke all on "better_supabase"."calendar_events" from public, anon, authenticated;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "better_supabase"."calendar_events";
create policy calendar_events_read on "better_supabase"."calendar_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_attendees" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "event_id" uuid not null references "better_supabase"."calendar_events" ("id") on delete cascade,
  "email" text not null,
  "name" text,
  "user_id" uuid,
  "role" text not null default 'required',
  "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative')),
  unique ("event_id", "email")
);
alter table "better_supabase"."calendar_attendees" enable row level security;
revoke all on "better_supabase"."calendar_attendees" from public, anon, authenticated;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    alter table "better_supabase"."calendar_attendees" add constraint "calendar_attendees_role_check"
      check ("role" in ('chair', 'required', 'optional', 'non-participant')) not valid;
    begin
      alter table "better_supabase"."calendar_attendees" validate constraint "calendar_attendees_role_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check', '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists calendar_attendees_read on "better_supabase"."calendar_attendees";
create policy calendar_attendees_read on "better_supabase"."calendar_attendees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
create table if not exists "better_supabase"."calendar_working_hours" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  "tz" text not null default 'UTC',
  check ("ends_at" > "starts_at"),
  unique ("tenant_id", "user_id", "weekday", "starts_at")
);
alter table "better_supabase"."calendar_working_hours" enable row level security;
revoke all on "better_supabase"."calendar_working_hours" from public, anon, authenticated;
grant select on "better_supabase"."calendar_working_hours" to authenticated;
grant all on "better_supabase"."calendar_working_hours" to service_role;
drop policy if exists calendar_working_hours_read on "better_supabase"."calendar_working_hours";
create policy calendar_working_hours_read on "better_supabase"."calendar_working_hours"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "better_supabase"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "better_supabase"."calendars" ("tenant_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "better_supabase"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "better_supabase"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "better_supabase"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  null;
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "better_supabase"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "better_supabase"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "better_supabase"."calendars" k
  where k."tenant_id" = list_calendars.tenant
$$;
revoke execute on function "better_supabase"."list_calendars"(uuid) from public, anon;
grant execute on function "better_supabase"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "better_supabase"."calendar_attendees" ("tenant_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "better_supabase"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "better_supabase"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "better_supabase"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$$;
revoke execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "better_supabase"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "better_supabase"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "better_supabase"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_attendees_auto_decline" on "better_supabase"."calendar_attendees";
create trigger "calendar_attendees_auto_decline"
before insert or update of "user_id" on "better_supabase"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "better_supabase"."calendar_attendee_auto_decline"();

create or replace function "better_supabase"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "better_supabase"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_events_auto_decline" on "better_supabase"."calendar_events";
create trigger "calendar_events_auto_decline"
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "better_supabase"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "better_supabase"."calendar_block_auto_decline"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
create policy bsb_tenant_scope_select on "better_supabase"."calendars" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
create policy bsb_tenant_scope_insert on "better_supabase"."calendars" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
create policy bsb_tenant_scope_update on "better_supabase"."calendars" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
create policy bsb_tenant_scope_delete on "better_supabase"."calendars" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_working_hours" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_working_hours" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.calendar.api: entry points for the Data API.
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

create or replace function "api"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_calendar"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."delete_calendar"(calendar_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_calendar"($1) $$;
revoke execute on function "api"."delete_calendar"(uuid) from public, anon;
grant execute on function "api"."delete_calendar"(uuid) to authenticated, service_role;

create or replace function "api"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_calendar_event"($1, $2) $$;
revoke execute on function "api"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_calendar_event"(event_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_calendar_event"($1) $$;
revoke execute on function "api"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "api"."delete_calendar_event"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_calendar_occurrence"($1, $2) $$;
revoke execute on function "api"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "api"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

create or replace function "api"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."split_calendar_event"($1, $2, $3, $4) $$;
revoke execute on function "api"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "api"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

create or replace function "api"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_calendar_events"($1, $2) $$;
revoke execute on function "api"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "api"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_calendar_events"($1, $2, $3) $$;
revoke execute on function "api"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "api"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."list_calendars"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_calendars"($1) $$;
revoke execute on function "api"."list_calendars"(uuid) from public, anon;
grant execute on function "api"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "api"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_calendar_attendee"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "api"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "api"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_calendar_attendee"($1, $2) $$;
revoke execute on function "api"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "api"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

create or replace function "api"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."respond_calendar_event"($1, $2) $$;
revoke execute on function "api"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "api"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "api"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."calendar_rule_starts"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "api"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."calendar_busy_blocks"($1, $2, $3, $4) $$;
revoke execute on function "api"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "api"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

create or replace function "api"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_calendar_working_hours"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "api"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_calendar_working_hours"($1, $2) $$;
revoke execute on function "api"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "api"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."calendar_free_busy"($1, $2, $3, $4) $$;
revoke execute on function "api"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "api"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:c26d60b3fa942e9609365661508f5e6d52e3c84afa95dcfcfcaad4ac9ea978a8
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.calendars is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."calendars" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."calendars" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."calendars" add column if not exists "name" text check (length("name") between 1 and 120);
alter table "better_supabase"."calendars" add column if not exists "tz" text not null default 'UTC';
alter table "better_supabase"."calendars" add column if not exists "color" text;
alter table "better_supabase"."calendars" add column if not exists "owner_type" text;
alter table "better_supabase"."calendars" add column if not exists "owner_id" text;
alter table "better_supabase"."calendars" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."calendars" enable row level security;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "better_supabase"."calendars" ("tenant_id");
drop policy if exists bsb_calendars_select on "better_supabase"."calendars";
create policy bsb_calendars_select on "better_supabase"."calendars"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
-- better_supabase.calendar_events is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."calendar_events" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."calendar_events" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."calendar_events" add column if not exists "calendar_id" uuid references "better_supabase"."calendars" ("id") on delete cascade;
alter table "better_supabase"."calendar_events" add column if not exists "uid" text;
alter table "better_supabase"."calendar_events" add column if not exists "title" text not null default '';
alter table "better_supabase"."calendar_events" add column if not exists "description" text;
alter table "better_supabase"."calendar_events" add column if not exists "location" text;
alter table "better_supabase"."calendar_events" add column if not exists "starts_at" timestamptz;
alter table "better_supabase"."calendar_events" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."calendar_events" add column if not exists "all_day" boolean not null default false;
alter table "better_supabase"."calendar_events" add column if not exists "tz" text not null default 'UTC';
alter table "better_supabase"."calendar_events" add column if not exists "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled'));
alter table "better_supabase"."calendar_events" add column if not exists "rrule" text;
alter table "better_supabase"."calendar_events" add column if not exists "exdates" timestamptz[] not null default '{}';
alter table "better_supabase"."calendar_events" add column if not exists "recurrence_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade;
alter table "better_supabase"."calendar_events" add column if not exists "original_start" timestamptz;
alter table "better_supabase"."calendar_events" add column if not exists "subject_type" text;
alter table "better_supabase"."calendar_events" add column if not exists "subject_id" text;
alter table "better_supabase"."calendar_events" add column if not exists "color" text;
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
alter table "better_supabase"."calendar_events" add column if not exists "created_by" uuid;
alter table "better_supabase"."calendar_events" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."calendar_events" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_kind_check', '"better_supabase"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_transparency_check', '"better_supabase"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."calendar_events" enable row level security;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists bsb_calendar_events_select on "better_supabase"."calendar_events";
create policy bsb_calendar_events_select on "better_supabase"."calendar_events"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')));
-- better_supabase.calendar_attendees is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."calendar_attendees" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."calendar_attendees" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."calendar_attendees" add column if not exists "event_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade;
alter table "better_supabase"."calendar_attendees" add column if not exists "email" text;
alter table "better_supabase"."calendar_attendees" add column if not exists "name" text;
alter table "better_supabase"."calendar_attendees" add column if not exists "user_id" uuid;
alter table "better_supabase"."calendar_attendees" add column if not exists "role" text not null default 'required';
alter table "better_supabase"."calendar_attendees" add column if not exists "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative'));
alter table "better_supabase"."calendar_attendees" enable row level security;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    begin
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check', '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists bsb_calendar_attendees_select on "better_supabase"."calendar_attendees";
create policy bsb_calendar_attendees_select on "better_supabase"."calendar_attendees"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
-- better_supabase.calendar_working_hours is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."calendar_working_hours" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."calendar_working_hours" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."calendar_working_hours" add column if not exists "user_id" uuid;
alter table "better_supabase"."calendar_working_hours" add column if not exists "weekday" smallint check ("weekday" between 1 and 7);
alter table "better_supabase"."calendar_working_hours" add column if not exists "starts_at" time;
alter table "better_supabase"."calendar_working_hours" add column if not exists "ends_at" time;
alter table "better_supabase"."calendar_working_hours" add column if not exists "tz" text not null default 'UTC';
alter table "better_supabase"."calendar_working_hours" enable row level security;
grant select on "better_supabase"."calendar_working_hours" to authenticated;
grant all on "better_supabase"."calendar_working_hours" to service_role;
drop policy if exists bsb_calendar_working_hours_select on "better_supabase"."calendar_working_hours";
create policy bsb_calendar_working_hours_select on "better_supabase"."calendar_working_hours"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "better_supabase"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "better_supabase"."calendars" ("tenant_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "better_supabase"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), better_supabase.as_column_type(coalesce(v_item ->> 'status', 'confirmed'), (null::"better_supabase"."calendar_events")."status"), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then better_supabase.as_column_type(coalesce(v_item ->> 'status', 'confirmed'), (null::"better_supabase"."calendar_events")."status") else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "better_supabase"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "better_supabase"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  null;
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "better_supabase"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "better_supabase"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "better_supabase"."calendars" k
  where k."tenant_id" = list_calendars.tenant
$$;
revoke execute on function "better_supabase"."list_calendars"(uuid) from public, anon;
grant execute on function "better_supabase"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "better_supabase"."calendar_attendees" ("tenant_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "better_supabase"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "better_supabase"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "better_supabase"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$$;
revoke execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "better_supabase"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "better_supabase"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "better_supabase"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists bsb_calendar_attendees_auto_decline on "better_supabase"."calendar_attendees";
create trigger bsb_calendar_attendees_auto_decline
before insert or update of "user_id" on "better_supabase"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "better_supabase"."calendar_attendee_auto_decline"();

create or replace function "better_supabase"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "better_supabase"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists bsb_calendar_events_auto_decline on "better_supabase"."calendar_events";
create trigger bsb_calendar_events_auto_decline
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "better_supabase"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "better_supabase"."calendar_block_auto_decline"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
create policy bsb_tenant_scope_select on "better_supabase"."calendars" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
create policy bsb_tenant_scope_insert on "better_supabase"."calendars" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
create policy bsb_tenant_scope_update on "better_supabase"."calendars" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
create policy bsb_tenant_scope_delete on "better_supabase"."calendars" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_events" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_events" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_events" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_events" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_working_hours" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_working_hours" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block calendar@1 managed
-- @bsb-hash sha256:491039ab51297ee55a9b767a546251195a9cd4b821b29834349da55e070fae97
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."calendars" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "tz" text not null default 'UTC',
  "color" text,
  "owner_type" text,
  "owner_id" text,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."calendars" enable row level security;
revoke all on "better_supabase"."calendars" from public, anon, authenticated;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
create index if not exists "calendars_tenant_idx" on "better_supabase"."calendars" ("org_id");
drop policy if exists calendars_read on "better_supabase"."calendars";
create policy calendars_read on "better_supabase"."calendars"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_events" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "calendar_id" uuid not null references "better_supabase"."calendars" ("id") on delete cascade,
  "uid" text not null,
  "title" text not null default '',
  "description" text,
  "location" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "all_day" boolean not null default false,
  "tz" text not null default 'UTC',
  "status" text not null default 'confirmed' check ("status" in ('confirmed', 'tentative', 'cancelled')),
  "rrule" text,
  "exdates" timestamptz[] not null default '{}',
  "recurrence_id" uuid references "better_supabase"."calendar_events" ("id") on delete cascade,
  "original_start" timestamptz,
  "subject_type" text,
  "subject_id" text,
  "color" text,
  "kind" text not null default 'event',
  "transparency" text not null default 'opaque',
  "auto_decline" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "kind" text not null default 'event';
alter table "better_supabase"."calendar_events" add column if not exists "transparency" text not null default 'opaque';
alter table "better_supabase"."calendar_events" add column if not exists "auto_decline" boolean not null default false;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_kind_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_kind_check"
      check ("kind" in ('event', 'out_of_office', 'focus_time')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_kind_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_kind_check', '"better_supabase"."calendar_events"', 'calendar_events_kind_check';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_events"'::regclass and conname = 'calendar_events_transparency_check'
  ) then
    alter table "better_supabase"."calendar_events" add constraint "calendar_events_transparency_check"
      check ("transparency" in ('opaque', 'transparent')) not valid;
    begin
      alter table "better_supabase"."calendar_events" validate constraint "calendar_events_transparency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_events"', 'calendar_events_transparency_check', '"better_supabase"."calendar_events"', 'calendar_events_transparency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."calendar_events" enable row level security;
revoke all on "better_supabase"."calendar_events" from public, anon, authenticated;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "better_supabase"."calendar_events";
create policy calendar_events_read on "better_supabase"."calendar_events"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')));
create table if not exists "better_supabase"."calendar_attendees" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "event_id" uuid not null references "better_supabase"."calendar_events" ("id") on delete cascade,
  "email" text not null,
  "name" text,
  "user_id" uuid,
  "role" text not null default 'required',
  "response" text not null default 'needs-action' check ("response" in ('needs-action', 'accepted', 'declined', 'tentative')),
  unique ("event_id", "email")
);
alter table "better_supabase"."calendar_attendees" enable row level security;
revoke all on "better_supabase"."calendar_attendees" from public, anon, authenticated;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."calendar_attendees"'::regclass and conname = 'calendar_attendees_role_check'
  ) then
    alter table "better_supabase"."calendar_attendees" add constraint "calendar_attendees_role_check"
      check ("role" in ('chair', 'required', 'optional', 'non-participant')) not valid;
    begin
      alter table "better_supabase"."calendar_attendees" validate constraint "calendar_attendees_role_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check', '"better_supabase"."calendar_attendees"', 'calendar_attendees_role_check';
    end;
  end if;
end;
$$;
drop policy if exists calendar_attendees_read on "better_supabase"."calendar_attendees";
create policy calendar_attendees_read on "better_supabase"."calendar_attendees"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));
create table if not exists "better_supabase"."calendar_working_hours" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid not null,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  "tz" text not null default 'UTC',
  check ("ends_at" > "starts_at"),
  unique ("org_id", "user_id", "weekday", "starts_at")
);
alter table "better_supabase"."calendar_working_hours" enable row level security;
revoke all on "better_supabase"."calendar_working_hours" from public, anon, authenticated;
grant select on "better_supabase"."calendar_working_hours" to authenticated;
grant all on "better_supabase"."calendar_working_hours" to service_role;
drop policy if exists calendar_working_hours_read on "better_supabase"."calendar_working_hours";
create policy calendar_working_hours_read on "better_supabase"."calendar_working_hours"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()));

create or replace function "better_supabase"."create_calendar"(tenant uuid, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_calendar.tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  insert into "better_supabase"."calendars" ("org_id", "name", "tz", "owner_type", "owner_id")
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC'), create_calendar.owner_type, create_calendar.owner_id)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_calendar"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar"(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.manage'), false)) then
    raise exception 'not allowed to manage calendars' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendars" where "id" = delete_calendar.calendar_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar"(uuid) to authenticated, service_role;

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function "better_supabase"."save_calendar_event"(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "org_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
revoke execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_calendar_event"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_calendar_event"(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events" where "id" = v_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_events" where "id" = v_id;
  
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_calendar_event"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_calendar_event"(uuid) to authenticated, service_role;

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function "better_supabase"."cancel_calendar_occurrence"(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant uuid;
  v_calendar uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id", "calendar_id" into v_tenant, v_calendar from "better_supabase"."calendar_events"
    where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  update "better_supabase"."calendar_events" set "exdates" = (
      select array_agg(distinct d order by d) from unnest(array_append("exdates", cancel_calendar_occurrence.original_start)) d
    ), "updated_at" = now()
  where "id" = v_id;
  delete from "better_supabase"."calendar_events" where "recurrence_id" = v_id and "original_start" = cancel_calendar_occurrence.original_start;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."cancel_calendar_occurrence"(uuid, timestamptz) to authenticated, service_role;

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function "better_supabase"."split_calendar_event"(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant uuid;
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id", "calendar_id", "uid", "starts_at", "exdates"
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from "better_supabase"."calendar_events" where "id" = v_id and "rrule" is not null for update;
  if not found then
    raise exception 'recurring event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    raise exception 'split at a later occurrence, with the rule that ends the series before it' using errcode = '22023', hint = 'CALENDAR_SPLIT_INVALID';
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update "better_supabase"."calendar_events" set "rrule" = split_calendar_event.before_rrule,
    "exdates" = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    "updated_at" = now()
  where "id" = v_id;
  
  v_new := "better_supabase"."save_calendar_event"(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update "better_supabase"."calendar_events" set "recurrence_id" = v_new_id, "uid" = v_new_uid, "updated_at" = now()
  where "recurrence_id" = v_id and "original_start" >= split_calendar_event.split_at;
  null;
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
revoke execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) from public, anon;
grant execute on function "better_supabase"."split_calendar_event"(uuid, timestamptz, text, jsonb) to authenticated, service_role;

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function "better_supabase"."import_calendar_events"(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null;
    else
      select "id" into v_master from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid' and "original_start" is null and "rrule" is not null;
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select "id" into v_id from "better_supabase"."calendar_events"
        where "calendar_id" = import_calendar_events.calendar_id and "uid" = v_item ->> 'uid'
          and "original_start" = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform "better_supabase"."save_calendar_event"(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_calendar_events"(uuid, jsonb) to authenticated, service_role;

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function "better_supabase"."list_calendar_events"(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
revoke execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_calendar_events"(uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."list_calendars"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") order by k."name"), '[]'::jsonb)
  from "better_supabase"."calendars" k
  where k."org_id" = list_calendars.tenant
$$;
revoke execute on function "better_supabase"."list_calendars"(uuid) from public, anon;
grant execute on function "better_supabase"."list_calendars"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."set_calendar_attendee"(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(set_calendar_attendee.role, 'required') not in ('chair', 'required', 'optional', 'non-participant') then
    raise exception 'role must be chair, required, optional or non-participant' using errcode = '22023', hint = 'CALENDAR_ROLE_INVALID';
  end if;
  select "org_id" into v_tenant from "better_supabase"."calendar_events" where "id" = set_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  insert into "better_supabase"."calendar_attendees" ("org_id", "event_id", "email", "name", "user_id", "role")
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict ("event_id", "email") do update
    set "name" = excluded."name", "user_id" = excluded."user_id", "role" = excluded."role";
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_calendar_attendee"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_calendar_attendee"(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."calendar_events" where "id" = remove_calendar_attendee.event_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  delete from "better_supabase"."calendar_attendees" where "event_id" = remove_calendar_attendee.event_id and "email" = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_calendar_attendee"(uuid, text) to authenticated, service_role;

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function "better_supabase"."respond_calendar_event"(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if respond_calendar_event.response not in ('needs-action', 'accepted', 'declined', 'tentative') then
    raise exception 'response must be needs-action, accepted, declined or tentative' using errcode = '22023', hint = 'CALENDAR_RESPONSE_INVALID';
  end if;
  update "better_supabase"."calendar_attendees" set "response" = respond_calendar_event.response,
    "user_id" = coalesce("user_id", auth.uid())
  where "event_id" = respond_calendar_event.event_id
    and ("user_id" = auth.uid() or ("user_id" is null and "email" = lower(auth.email())));
  if not found then
    raise exception 'you are not invited to this event' using errcode = 'P0002', hint = 'CALENDAR_ATTENDEE_NOT_FOUND';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."respond_calendar_event"(uuid, text) from public, anon;
grant execute on function "better_supabase"."respond_calendar_event"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."calendar_rule_starts"(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_rule_starts"(timestamptz, text, text, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_busy_blocks"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."org_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."org_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."org_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$$;
revoke execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamptz, timestamptz) to service_role;

-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function "better_supabase"."set_calendar_working_hours"(tenant uuid, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "org_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("org_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function "better_supabase"."list_calendar_working_hours"(tenant uuid, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."org_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$$;
revoke execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) to authenticated, service_role;

-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function "better_supabase"."calendar_free_busy"(tenant uuid, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."org_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
revoke execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamptz, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."calendar_attendee_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x."org_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."calendar_attendee_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_attendees_auto_decline" on "better_supabase"."calendar_attendees";
create trigger "calendar_attendees_auto_decline"
before insert or update of "user_id" on "better_supabase"."calendar_attendees"
for each row
when (new."user_id" is not null and new."response" = 'needs-action')
execute function "better_supabase"."calendar_attendee_auto_decline"();

create or replace function "better_supabase"."calendar_block_auto_decline"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."org_id" = new."org_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$$;
revoke execute on function "better_supabase"."calendar_block_auto_decline"() from public, anon, authenticated;
drop trigger if exists "calendar_events_auto_decline" on "better_supabase"."calendar_events";
create trigger "calendar_events_auto_decline"
after insert or update of "starts_at", "ends_at", "kind", "auto_decline", "status" on "better_supabase"."calendar_events"
for each row
when (new."kind" <> 'event' and new."auto_decline" and new."status" <> 'cancelled' and new."rrule" is null)
execute function "better_supabase"."calendar_block_auto_decline"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."calendars";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendars";
create policy bsb_tenant_scope_select on "better_supabase"."calendars" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendars";
create policy bsb_tenant_scope_insert on "better_supabase"."calendars" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendars";
create policy bsb_tenant_scope_update on "better_supabase"."calendars" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendars";
create policy bsb_tenant_scope_delete on "better_supabase"."calendars" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_events";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_events" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_events" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_events" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_events";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_events" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_attendees" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_attendees" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_attendees" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_attendees" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."calendar_working_hours";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_select on "better_supabase"."calendar_working_hours" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('calendar.read')) or "user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_insert on "better_supabase"."calendar_working_hours" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_update on "better_supabase"."calendar_working_hours" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours";
create policy bsb_tenant_scope_delete on "better_supabase"."calendar_working_hours" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_072_calendar.sql
-- better-supabase module: calendar
-- @bsb-block-data calendar
-- @bsb-hash sha256:d394b8cd042344b4f2cc937a4b1a75f47403ab3daa823c307e6f4711cc462311
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
