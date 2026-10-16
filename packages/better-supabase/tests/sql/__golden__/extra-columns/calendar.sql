-- ==== schema supabase/schemas/900_better_supabase_72_calendar.sql
-- better-supabase module: calendar
-- @bs-module calendar@1 managed
-- Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees. Series expand in TypeScript with the reminders block's expandRule; a share link serves an iCal feed.
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
revoke all on "better_supabase"."calendars" from anon, authenticated;
grant select on "better_supabase"."calendars" to authenticated;
grant all on "better_supabase"."calendars" to service_role;
drop policy if exists calendars_read on "better_supabase"."calendars";
create policy calendars_read on "better_supabase"."calendars" for select to authenticated
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
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" >= "starts_at"),
  check (("recurrence_id" is null) = ("original_start" is null)),
  unique nulls not distinct ("calendar_id", "uid", "original_start")
);
create index if not exists calendar_events_recurrence_idx on "better_supabase"."calendar_events" ("recurrence_id") where "recurrence_id" is not null;
create index if not exists calendar_events_range_idx on "better_supabase"."calendar_events" ("calendar_id", "starts_at");
alter table "better_supabase"."calendar_events" add column if not exists "app_note" text;
alter table "better_supabase"."calendar_events" enable row level security;
revoke all on "better_supabase"."calendar_events" from anon, authenticated;
grant select on "better_supabase"."calendar_events" to authenticated;
grant all on "better_supabase"."calendar_events" to service_role;
drop policy if exists calendar_events_read on "better_supabase"."calendar_events";
create policy calendar_events_read on "better_supabase"."calendar_events" for select to authenticated
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
revoke all on "better_supabase"."calendar_attendees" from anon, authenticated;
grant select on "better_supabase"."calendar_attendees" to authenticated;
grant all on "better_supabase"."calendar_attendees" to service_role;
drop policy if exists calendar_attendees_read on "better_supabase"."calendar_attendees";
create policy calendar_attendees_read on "better_supabase"."calendar_attendees" for select to authenticated
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
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
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
  update "better_supabase"."calendar_events" x set "app_note" = case when v_item ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."calendar_events", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(v_item) e where e.key in ('app_note'))) r
  where x."id" = v_id;
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
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', e."app_note")) order by e."starts_at", e."id"), '[]'::jsonb)
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

-- ==== data supabase/better-supabase-data/900_better_supabase_72_calendar.sql
-- better-supabase module: calendar
-- @bs-module-data calendar
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
