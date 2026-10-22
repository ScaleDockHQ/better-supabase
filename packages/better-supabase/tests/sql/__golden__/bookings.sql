-- ==== alone: schema supabase/schemas/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module bookings@1 managed
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
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
create extension if not exists btree_gist with schema extensions;
create table if not exists "better_supabase"."booking_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "kind" text not null default 'staff',
  "capacity" integer not null default 1 check ("capacity" between 1 and 1000),
  "tz" text not null default 'UTC',
  "calendar_id" uuid,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_resources" enable row level security;
revoke all on "better_supabase"."booking_resources" from anon, authenticated;
grant select on "better_supabase"."booking_resources" to authenticated;
grant all on "better_supabase"."booking_resources" to service_role;
create index if not exists "booking_resources_tenant_idx" on "better_supabase"."booking_resources" ("tenant_id");
drop policy if exists booking_resources_read on "better_supabase"."booking_resources";
create policy booking_resources_read on "better_supabase"."booking_resources" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  check ("ends_at" > "starts_at")
);
create index if not exists booking_availability_resource_idx on "better_supabase"."booking_availability" ("resource_id", "weekday");
alter table "better_supabase"."booking_availability" enable row level security;
revoke all on "better_supabase"."booking_availability" from anon, authenticated;
grant select on "better_supabase"."booking_availability" to authenticated;
grant all on "better_supabase"."booking_availability" to service_role;
drop policy if exists booking_availability_read on "better_supabase"."booking_availability";
create policy booking_availability_read on "better_supabase"."booking_availability" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_exceptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "during" tstzrange not null check (not isempty("during")),
  "available" boolean not null default false,
  "reason" text
);
create index if not exists booking_exceptions_resource_idx on "better_supabase"."booking_exceptions" using gist ("resource_id", "during");
alter table "better_supabase"."booking_exceptions" enable row level security;
revoke all on "better_supabase"."booking_exceptions" from anon, authenticated;
grant select on "better_supabase"."booking_exceptions" to authenticated;
grant all on "better_supabase"."booking_exceptions" to service_role;
drop policy if exists booking_exceptions_read on "better_supabase"."booking_exceptions";
create policy booking_exceptions_read on "better_supabase"."booking_exceptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')));
create table if not exists "better_supabase"."booking_services" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "duration" interval not null check ("duration" > interval '0'),
  "buffer_before" interval not null default interval '0' check ("buffer_before" >= interval '0'),
  "buffer_after" interval not null default interval '0' check ("buffer_after" >= interval '0'),
  "resource_kinds" text[] not null default '{}',
  "step" interval check ("step" > interval '0'),
  "min_notice" interval not null default interval '0',
  "hold_for" interval not null default interval '10 minutes' check ("hold_for" > interval '0'),
  "reminder_offsets" integer[] not null default '{1440}',
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_services" enable row level security;
revoke all on "better_supabase"."booking_services" from anon, authenticated;
grant select on "better_supabase"."booking_services" to authenticated;
grant all on "better_supabase"."booking_services" to service_role;
create index if not exists "booking_services_tenant_idx" on "better_supabase"."booking_services" ("tenant_id");
drop policy if exists booking_services_read on "better_supabase"."booking_services";
create policy booking_services_read on "better_supabase"."booking_services" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."bookings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "service_id" uuid not null references "better_supabase"."booking_services" ("id") on delete restrict,
  "seat" integer not null default 1 check ("seat" >= 1),
  "during" tstzrange not null check (not isempty("during")),
  "blocked" tstzrange not null,
  "status" text not null default 'hold' check ("status" in ('hold', 'confirmed', 'cancelled')),
  "hold_expires_at" timestamptz,
  "customer_name" text,
  "customer_email" text,
  "customer_user_id" uuid,
  "notes" text,
  "access_hash" text unique,
  "calendar_event_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  check ("blocked" @> "during"),
  check (("status" = 'hold') = ("hold_expires_at" is not null)),
  constraint bookings_no_overlap exclude using gist (
    "resource_id" with =,
    "seat" with =,
    "blocked" with &&
  ) where ("status" <> 'cancelled')
);
create index if not exists bookings_tenant_during_idx on "better_supabase"."bookings" using gist ("tenant_id", "during");
create index if not exists bookings_resource_idx on "better_supabase"."bookings" ("resource_id");
create index if not exists bookings_service_idx on "better_supabase"."bookings" ("service_id");
create index if not exists bookings_hold_idx on "better_supabase"."bookings" ("hold_expires_at") where "status" = 'hold';
alter table "better_supabase"."bookings" enable row level security;
revoke all on "better_supabase"."bookings" from anon, authenticated;
grant select on "better_supabase"."bookings" to authenticated;
grant all on "better_supabase"."bookings" to service_role;
drop policy if exists bookings_read on "better_supabase"."bookings";
create policy bookings_read on "better_supabase"."bookings" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_user_id" = (select auth.uid()));

create or replace function "better_supabase"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function "better_supabase"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = set_booking_availability.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_availability" where "resource_id" = set_booking_availability.resource;
  insert into "better_supabase"."booking_availability" ("tenant_id", "resource_id", "weekday", "starts_at", "ends_at")
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function "better_supabase"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = add_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "better_supabase"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_booking_exception"(exception_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant uuid := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_services" ("tenant_id", "name", "duration", "buffer_before", "buffer_after", "resource_kinds", "step", "min_notice", "hold_for", "active", "reminder_offsets")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'duration' then (v_item ->> 'duration')::interval else null end, case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else interval '0' end, case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else interval '0' end, case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else '{}'::text[] end, case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else null end, case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else interval '0' end, case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else interval '10 minutes' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else '{1440}'::integer[] end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_services" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "duration" = case when v_item ? 'duration' then (v_item ->> 'duration')::interval else "duration" end, "buffer_before" = case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else "buffer_before" end, "buffer_after" = case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else "buffer_after" end, "resource_kinds" = case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else "resource_kinds" end, "step" = case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else "step" end, "min_notice" = case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else "min_notice" end, "hold_for" = case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else "hold_for" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "reminder_offsets" = case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else "reminder_offsets" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it.
-- local_start is the start in tz (default the resource's zone).
create or replace function "better_supabase"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "better_supabase"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = available_slots.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)) or (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false))) then
    raise exception 'not allowed to read bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(available_slots.service, available_slots.range_start, available_slots.range_end, available_slots.tz, available_slots.resource) t), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function "better_supabase"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'expired', "updated_at" = now()
    where bk."status" = 'hold' and bk."hold_expires_at" <= now()
      and (expire_booking_holds_in.resource is null or bk."resource_id" = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk."blocked" && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "better_supabase"."expire_booking_holds"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."expire_booking_holds_in"(null, null)
$$;
revoke execute on function "better_supabase"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds"() to service_role;

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function "better_supabase"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  null;
  if v_status = 'confirmed' then
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$$;
revoke execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function "better_supabase"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = hold_booking.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return "better_supabase"."place_booking"(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
revoke execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function "better_supabase"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$$;
revoke execute on function "better_supabase"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "better_supabase"."confirm_booking"(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(confirm_booking.booking, 'confirmed', null, null)
$$;
revoke execute on function "better_supabase"."confirm_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
revoke execute on function "better_supabase"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_booking"(uuid, text) to authenticated, service_role;

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function "better_supabase"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$$;
revoke execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module-data bookings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module bookings@1 managed
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
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
create extension if not exists btree_gist with schema extensions;
create table if not exists "better_supabase"."booking_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "kind" text not null default 'staff',
  "capacity" integer not null default 1 check ("capacity" between 1 and 1000),
  "tz" text not null default 'UTC',
  "calendar_id" uuid,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_resources" enable row level security;
revoke all on "better_supabase"."booking_resources" from anon, authenticated;
grant select on "better_supabase"."booking_resources" to authenticated;
grant all on "better_supabase"."booking_resources" to service_role;
create index if not exists "booking_resources_tenant_idx" on "better_supabase"."booking_resources" ("tenant_id");
drop policy if exists booking_resources_read on "better_supabase"."booking_resources";
create policy booking_resources_read on "better_supabase"."booking_resources" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  check ("ends_at" > "starts_at")
);
create index if not exists booking_availability_resource_idx on "better_supabase"."booking_availability" ("resource_id", "weekday");
alter table "better_supabase"."booking_availability" enable row level security;
revoke all on "better_supabase"."booking_availability" from anon, authenticated;
grant select on "better_supabase"."booking_availability" to authenticated;
grant all on "better_supabase"."booking_availability" to service_role;
drop policy if exists booking_availability_read on "better_supabase"."booking_availability";
create policy booking_availability_read on "better_supabase"."booking_availability" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_exceptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "during" tstzrange not null check (not isempty("during")),
  "available" boolean not null default false,
  "reason" text
);
create index if not exists booking_exceptions_resource_idx on "better_supabase"."booking_exceptions" using gist ("resource_id", "during");
alter table "better_supabase"."booking_exceptions" enable row level security;
revoke all on "better_supabase"."booking_exceptions" from anon, authenticated;
grant select on "better_supabase"."booking_exceptions" to authenticated;
grant all on "better_supabase"."booking_exceptions" to service_role;
drop policy if exists booking_exceptions_read on "better_supabase"."booking_exceptions";
create policy booking_exceptions_read on "better_supabase"."booking_exceptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')));
create table if not exists "better_supabase"."booking_services" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "duration" interval not null check ("duration" > interval '0'),
  "buffer_before" interval not null default interval '0' check ("buffer_before" >= interval '0'),
  "buffer_after" interval not null default interval '0' check ("buffer_after" >= interval '0'),
  "resource_kinds" text[] not null default '{}',
  "step" interval check ("step" > interval '0'),
  "min_notice" interval not null default interval '0',
  "hold_for" interval not null default interval '10 minutes' check ("hold_for" > interval '0'),
  "reminder_offsets" integer[] not null default '{1440}',
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_services" enable row level security;
revoke all on "better_supabase"."booking_services" from anon, authenticated;
grant select on "better_supabase"."booking_services" to authenticated;
grant all on "better_supabase"."booking_services" to service_role;
create index if not exists "booking_services_tenant_idx" on "better_supabase"."booking_services" ("tenant_id");
drop policy if exists booking_services_read on "better_supabase"."booking_services";
create policy booking_services_read on "better_supabase"."booking_services" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."bookings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "service_id" uuid not null references "better_supabase"."booking_services" ("id") on delete restrict,
  "seat" integer not null default 1 check ("seat" >= 1),
  "during" tstzrange not null check (not isempty("during")),
  "blocked" tstzrange not null,
  "status" text not null default 'hold' check ("status" in ('hold', 'confirmed', 'cancelled')),
  "hold_expires_at" timestamptz,
  "customer_name" text,
  "customer_email" text,
  "customer_user_id" uuid,
  "notes" text,
  "access_hash" text unique,
  "calendar_event_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  check ("blocked" @> "during"),
  check (("status" = 'hold') = ("hold_expires_at" is not null)),
  constraint bookings_no_overlap exclude using gist (
    "resource_id" with =,
    "seat" with =,
    "blocked" with &&
  ) where ("status" <> 'cancelled')
);
create index if not exists bookings_tenant_during_idx on "better_supabase"."bookings" using gist ("tenant_id", "during");
create index if not exists bookings_resource_idx on "better_supabase"."bookings" ("resource_id");
create index if not exists bookings_service_idx on "better_supabase"."bookings" ("service_id");
create index if not exists bookings_hold_idx on "better_supabase"."bookings" ("hold_expires_at") where "status" = 'hold';
alter table "better_supabase"."bookings" enable row level security;
revoke all on "better_supabase"."bookings" from anon, authenticated;
grant select on "better_supabase"."bookings" to authenticated;
grant all on "better_supabase"."bookings" to service_role;
drop policy if exists bookings_read on "better_supabase"."bookings";
create policy bookings_read on "better_supabase"."bookings" for select to authenticated
using (("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_user_id" = (select auth.uid())) or (("tenant_id")::text, ('booking')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g));

create or replace function "better_supabase"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function "better_supabase"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = set_booking_availability.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_availability" where "resource_id" = set_booking_availability.resource;
  insert into "better_supabase"."booking_availability" ("tenant_id", "resource_id", "weekday", "starts_at", "ends_at")
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function "better_supabase"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = add_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "better_supabase"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_booking_exception"(exception_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant uuid := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_services" ("tenant_id", "name", "duration", "buffer_before", "buffer_after", "resource_kinds", "step", "min_notice", "hold_for", "active", "reminder_offsets")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'duration' then (v_item ->> 'duration')::interval else null end, case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else interval '0' end, case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else interval '0' end, case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else '{}'::text[] end, case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else null end, case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else interval '0' end, case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else interval '10 minutes' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else '{1440}'::integer[] end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_services" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "duration" = case when v_item ? 'duration' then (v_item ->> 'duration')::interval else "duration" end, "buffer_before" = case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else "buffer_before" end, "buffer_after" = case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else "buffer_after" end, "resource_kinds" = case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else "resource_kinds" end, "step" = case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else "step" end, "min_notice" = case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else "min_notice" end, "hold_for" = case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else "hold_for" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "reminder_offsets" = case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else "reminder_offsets" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it.
-- local_start is the start in tz (default the resource's zone).
create or replace function "better_supabase"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "better_supabase"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = available_slots.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)) or (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false))) then
    raise exception 'not allowed to read bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(available_slots.service, available_slots.range_start, available_slots.range_end, available_slots.tz, available_slots.resource) t), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function "better_supabase"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'expired', "updated_at" = now()
    where bk."status" = 'hold' and bk."hold_expires_at" <= now()
      and (expire_booking_holds_in.resource is null or bk."resource_id" = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk."blocked" && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    perform "better_supabase".emit_event('booking.expired', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "better_supabase"."expire_booking_holds"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."expire_booking_holds_in"(null, null)
$$;
revoke execute on function "better_supabase"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds"() to service_role;

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function "better_supabase"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  perform "better_supabase".emit_event('booking.reserved', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  if v_status = 'confirmed' then
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_start") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  if v_status = 'hold' then
    perform "better_supabase"."enqueue_job"(queue => 'bookings.expire-holds', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$$;
revoke execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function "better_supabase"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = hold_booking.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return "better_supabase"."place_booking"(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
revoke execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function "better_supabase"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_start") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    if v_booking."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_booking."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    perform "better_supabase".emit_event('booking.cancelled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$$;
revoke execute on function "better_supabase"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "better_supabase"."confirm_booking"(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(confirm_booking.booking, 'confirmed', null, null)
$$;
revoke execute on function "better_supabase"."confirm_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
revoke execute on function "better_supabase"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_booking"(uuid, text) to authenticated, service_role;

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function "better_supabase"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$$;
revoke execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

-- Public booking through a share link to a service (subjectType
-- "booking_service"): the token is the credential, hashed before the lookup.
create or replace function "better_supabase"."public_booking_service"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_booking_service.token is null or public_booking_service.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_booking_service.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from better_supabase.rate_limit_rules q where q.scope = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  return (
    select jsonb_build_object('id', sv."id", 'name', sv."name", 'duration', sv."duration"::text,
      'resources', coalesce((
        select jsonb_agg(jsonb_build_object('id', rs."id", 'name', rs."name", 'kind', rs."kind", 'tz', rs."tz") order by rs."name")
        from "better_supabase"."booking_resources" rs
        where rs."tenant_id" = sv."tenant_id" and rs."active"
          and (cardinality(sv."resource_kinds") = 0 or rs."kind" = any (sv."resource_kinds"))
      ), '[]'::jsonb))
    from "better_supabase"."booking_services" sv where sv."id" = v_service
  );
end;
$$;
revoke all on function "better_supabase"."public_booking_service"(text) from public;
grant execute on function "better_supabase"."public_booking_service"(text) to anon, authenticated, service_role;

create or replace function "better_supabase"."public_available_slots"(token text, range_start timestamptz, range_end timestamptz, tz text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_available_slots.token is null or public_available_slots.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_available_slots.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from better_supabase.rate_limit_rules q where q.scope = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  if public_available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = public_available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if public_available_slots.range_end - public_available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(v_service, public_available_slots.range_start, public_available_slots.range_end, public_available_slots.tz, null) t), '[]'::jsonb);
end;
$$;
revoke all on function "better_supabase"."public_available_slots"(text, timestamptz, timestamptz, text) from public;
grant execute on function "better_supabase"."public_available_slots"(text, timestamptz, timestamptz, text) to anon, authenticated, service_role;

-- A guest holds a slot. The result's accessToken confirms or cancels it
-- later; it is returned once and stored hashed.
create or replace function "better_supabase"."public_hold_booking"(token text, resource uuid, starts_at timestamptz, customer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;
begin
  if public_hold_booking.token is null or public_hold_booking.token !~ '^[0-9a-f]{32,128}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l."id", l."subject_id", l."tenant_id"::text into v_link, v_subject, v_link_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(public_hold_booking.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'booking_service'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select sv."id" into v_service from "better_supabase"."booking_services" sv
    where sv."id" = v_subject::uuid and sv."tenant_id"::text = v_link_tenant and sv."active";
  if not found then
    raise exception 'unknown or expired booking link' using errcode = 'P0002', hint = 'BOOKING_LINK_INVALID';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    v_link::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from better_supabase.rate_limit_rules q where q.scope = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  if nullif(trim(public_hold_booking.customer ->> 'name'), '') is null
    or coalesce(public_hold_booking.customer ->> 'email', '') !~ '^[^@\s]+@[^@\s]+$' then
    raise exception 'a guest booking needs a name and an email' using errcode = '22023', hint = 'BOOKING_CUSTOMER_INVALID';
  end if;
  return "better_supabase"."place_booking"(v_service, public_hold_booking.resource, public_hold_booking.starts_at, public_hold_booking.customer - 'userId', false, auth.uid());
end;
$$;
revoke all on function "better_supabase"."public_hold_booking"(text, uuid, timestamptz, jsonb) from public;
grant execute on function "better_supabase"."public_hold_booking"(text, uuid, timestamptz, jsonb) to anon, authenticated, service_role;

create or replace function "better_supabase"."public_change_booking"(booking uuid, access_token text, to_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_allowed boolean;
  v_retry integer;
begin
  if public_change_booking.access_token is null or public_change_booking.access_token !~ '^[0-9a-f]{48}$' then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    'bookings.public',
    public_change_booking.booking::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from better_supabase.rate_limit_rules q where q.scope = 'bookings.public') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  return "better_supabase"."change_booking"(public_change_booking.booking, public_change_booking.to_status, case when public_change_booking.to_status = 'cancelled' then 'customer' end, public_change_booking.access_token);
end;
$$;
revoke all on function "better_supabase"."public_change_booking"(uuid, text, text) from public;
grant execute on function "better_supabase"."public_change_booking"(uuid, text, text) to anon, authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module-data bookings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module bookings@1 managed
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create extension if not exists btree_gist with schema extensions;
create table if not exists "app_private"."booking_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "kind" text not null default 'staff',
  "capacity" integer not null default 1 check ("capacity" between 1 and 1000),
  "tz" text not null default 'UTC',
  "calendar_id" uuid,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."booking_resources" enable row level security;
revoke all on "app_private"."booking_resources" from anon, authenticated;
grant select on "app_private"."booking_resources" to authenticated;
grant all on "app_private"."booking_resources" to service_role;
create index if not exists "booking_resources_tenant_idx" on "app_private"."booking_resources" ("tenant_id");
drop policy if exists booking_resources_read on "app_private"."booking_resources";
create policy booking_resources_read on "app_private"."booking_resources" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "app_private"."booking_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "app_private"."booking_resources" ("id") on delete cascade,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  check ("ends_at" > "starts_at")
);
create index if not exists booking_availability_resource_idx on "app_private"."booking_availability" ("resource_id", "weekday");
alter table "app_private"."booking_availability" enable row level security;
revoke all on "app_private"."booking_availability" from anon, authenticated;
grant select on "app_private"."booking_availability" to authenticated;
grant all on "app_private"."booking_availability" to service_role;
drop policy if exists booking_availability_read on "app_private"."booking_availability";
create policy booking_availability_read on "app_private"."booking_availability" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "app_private"."booking_exceptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "app_private"."booking_resources" ("id") on delete cascade,
  "during" tstzrange not null check (not isempty("during")),
  "available" boolean not null default false,
  "reason" text
);
create index if not exists booking_exceptions_resource_idx on "app_private"."booking_exceptions" using gist ("resource_id", "during");
alter table "app_private"."booking_exceptions" enable row level security;
revoke all on "app_private"."booking_exceptions" from anon, authenticated;
grant select on "app_private"."booking_exceptions" to authenticated;
grant all on "app_private"."booking_exceptions" to service_role;
drop policy if exists booking_exceptions_read on "app_private"."booking_exceptions";
create policy booking_exceptions_read on "app_private"."booking_exceptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')));
create table if not exists "app_private"."booking_services" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "duration" interval not null check ("duration" > interval '0'),
  "buffer_before" interval not null default interval '0' check ("buffer_before" >= interval '0'),
  "buffer_after" interval not null default interval '0' check ("buffer_after" >= interval '0'),
  "resource_kinds" text[] not null default '{}',
  "step" interval check ("step" > interval '0'),
  "min_notice" interval not null default interval '0',
  "hold_for" interval not null default interval '10 minutes' check ("hold_for" > interval '0'),
  "reminder_offsets" integer[] not null default '{1440}',
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."booking_services" enable row level security;
revoke all on "app_private"."booking_services" from anon, authenticated;
grant select on "app_private"."booking_services" to authenticated;
grant all on "app_private"."booking_services" to service_role;
create index if not exists "booking_services_tenant_idx" on "app_private"."booking_services" ("tenant_id");
drop policy if exists booking_services_read on "app_private"."booking_services";
create policy booking_services_read on "app_private"."booking_services" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "app_private"."bookings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "app_private"."booking_resources" ("id") on delete cascade,
  "service_id" uuid not null references "app_private"."booking_services" ("id") on delete restrict,
  "seat" integer not null default 1 check ("seat" >= 1),
  "during" tstzrange not null check (not isempty("during")),
  "blocked" tstzrange not null,
  "status" text not null default 'hold' check ("status" in ('hold', 'confirmed', 'cancelled')),
  "hold_expires_at" timestamptz,
  "customer_name" text,
  "customer_email" text,
  "customer_user_id" uuid,
  "notes" text,
  "access_hash" text unique,
  "calendar_event_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  check ("blocked" @> "during"),
  check (("status" = 'hold') = ("hold_expires_at" is not null)),
  constraint bookings_no_overlap exclude using gist (
    "resource_id" with =,
    "seat" with =,
    "blocked" with &&
  ) where ("status" <> 'cancelled')
);
create index if not exists bookings_tenant_during_idx on "app_private"."bookings" using gist ("tenant_id", "during");
create index if not exists bookings_resource_idx on "app_private"."bookings" ("resource_id");
create index if not exists bookings_service_idx on "app_private"."bookings" ("service_id");
create index if not exists bookings_hold_idx on "app_private"."bookings" ("hold_expires_at") where "status" = 'hold';
alter table "app_private"."bookings" enable row level security;
revoke all on "app_private"."bookings" from anon, authenticated;
grant select on "app_private"."bookings" to authenticated;
grant all on "app_private"."bookings" to service_role;
drop policy if exists bookings_read on "app_private"."bookings";
create policy bookings_read on "app_private"."bookings" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_user_id" = (select auth.uid()));

create or replace function "app_private"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "app_private"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end)
    returning "id" into v_id;
  else
    update "app_private"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function "app_private"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."booking_resources" where "id" = set_booking_availability.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "app_private"."booking_availability" where "resource_id" = set_booking_availability.resource;
  insert into "app_private"."booking_availability" ("tenant_id", "resource_id", "weekday", "starts_at", "ends_at")
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function "app_private"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."booking_resources" where "id" = add_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "app_private"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "app_private"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "app_private"."delete_booking_exception"(exception_id uuid)
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
  select "tenant_id" into v_tenant from "app_private"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "app_private"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "app_private"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "app_private"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant uuid := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_id is null then
    insert into "app_private"."booking_services" ("tenant_id", "name", "duration", "buffer_before", "buffer_after", "resource_kinds", "step", "min_notice", "hold_for", "active", "reminder_offsets")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'duration' then (v_item ->> 'duration')::interval else null end, case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else interval '0' end, case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else interval '0' end, case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else '{}'::text[] end, case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else null end, case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else interval '0' end, case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else interval '10 minutes' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else '{1440}'::integer[] end)
    returning "id" into v_id;
  else
    update "app_private"."booking_services" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "duration" = case when v_item ? 'duration' then (v_item ->> 'duration')::interval else "duration" end, "buffer_before" = case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else "buffer_before" end, "buffer_after" = case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else "buffer_after" end, "resource_kinds" = case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else "resource_kinds" end, "step" = case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else "step" end, "min_notice" = case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else "min_notice" end, "hold_for" = case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else "hold_for" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "reminder_offsets" = case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else "reminder_offsets" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it.
-- local_start is the start in tz (default the resource's zone).
create or replace function "app_private"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "app_private"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity
    from "app_private"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "app_private"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "app_private"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "app_private"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "app_private"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
revoke execute on function "app_private"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "app_private"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "app_private"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "app_private"."booking_services" where "id" = available_slots.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)) or (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false))) then
    raise exception 'not allowed to read bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "app_private"."booking_slots"(available_slots.service, available_slots.range_start, available_slots.range_end, available_slots.tz, available_slots.resource) t), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "app_private"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function "app_private"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "app_private"."bookings"%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update "app_private"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'expired', "updated_at" = now()
    where bk."status" = 'hold' and bk."hold_expires_at" <= now()
      and (expire_booking_holds_in.resource is null or bk."resource_id" = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk."blocked" && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "app_private"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "app_private"."expire_booking_holds"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select "app_private"."expire_booking_holds_in"(null, null)
$$;
revoke execute on function "app_private"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "app_private"."expire_booking_holds"() to service_role;

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function "app_private"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "app_private"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "app_private"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "app_private"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "app_private"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "app_private"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "app_private"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "app_private"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  null;
  if v_status = 'confirmed' then
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$$;
revoke execute on function "app_private"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "app_private"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function "app_private"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select "tenant_id" into v_tenant from "app_private"."booking_services" where "id" = hold_booking.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return "app_private"."place_booking"(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
revoke execute on function "app_private"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "app_private"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function "app_private"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "app_private"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "app_private"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "app_private"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "app_private"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$$;
revoke execute on function "app_private"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "app_private"."confirm_booking"(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "app_private"."change_booking"(confirm_booking.booking, 'confirmed', null, null)
$$;
revoke execute on function "app_private"."confirm_booking"(uuid) from public, anon;
grant execute on function "app_private"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "app_private"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "app_private"."change_booking"(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
revoke execute on function "app_private"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_booking"(uuid, text) to authenticated, service_role;

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function "app_private"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "app_private"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$$;
revoke execute on function "app_private"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "app_private"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module-data bookings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module bookings@1 managed
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
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
create extension if not exists btree_gist with schema extensions;
create table if not exists "better_supabase"."booking_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "kind" text not null default 'staff',
  "capacity" integer not null default 1 check ("capacity" between 1 and 1000),
  "tz" text not null default 'UTC',
  "calendar_id" uuid,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_resources" enable row level security;
revoke all on "better_supabase"."booking_resources" from anon, authenticated;
grant select on "better_supabase"."booking_resources" to authenticated;
grant all on "better_supabase"."booking_resources" to service_role;
create index if not exists "booking_resources_tenant_idx" on "better_supabase"."booking_resources" ("tenant_id");
drop policy if exists booking_resources_read on "better_supabase"."booking_resources";
create policy booking_resources_read on "better_supabase"."booking_resources" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "weekday" smallint not null check ("weekday" between 1 and 7),
  "starts_at" time not null,
  "ends_at" time not null,
  check ("ends_at" > "starts_at")
);
create index if not exists booking_availability_resource_idx on "better_supabase"."booking_availability" ("resource_id", "weekday");
alter table "better_supabase"."booking_availability" enable row level security;
revoke all on "better_supabase"."booking_availability" from anon, authenticated;
grant select on "better_supabase"."booking_availability" to authenticated;
grant all on "better_supabase"."booking_availability" to service_role;
drop policy if exists booking_availability_read on "better_supabase"."booking_availability";
create policy booking_availability_read on "better_supabase"."booking_availability" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."booking_exceptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "during" tstzrange not null check (not isempty("during")),
  "available" boolean not null default false,
  "reason" text
);
create index if not exists booking_exceptions_resource_idx on "better_supabase"."booking_exceptions" using gist ("resource_id", "during");
alter table "better_supabase"."booking_exceptions" enable row level security;
revoke all on "better_supabase"."booking_exceptions" from anon, authenticated;
grant select on "better_supabase"."booking_exceptions" to authenticated;
grant all on "better_supabase"."booking_exceptions" to service_role;
drop policy if exists booking_exceptions_read on "better_supabase"."booking_exceptions";
create policy booking_exceptions_read on "better_supabase"."booking_exceptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')));
create table if not exists "better_supabase"."booking_services" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "duration" interval not null check ("duration" > interval '0'),
  "buffer_before" interval not null default interval '0' check ("buffer_before" >= interval '0'),
  "buffer_after" interval not null default interval '0' check ("buffer_after" >= interval '0'),
  "resource_kinds" text[] not null default '{}',
  "step" interval check ("step" > interval '0'),
  "min_notice" interval not null default interval '0',
  "hold_for" interval not null default interval '10 minutes' check ("hold_for" > interval '0'),
  "reminder_offsets" integer[] not null default '{1440}',
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_services" enable row level security;
revoke all on "better_supabase"."booking_services" from anon, authenticated;
grant select on "better_supabase"."booking_services" to authenticated;
grant all on "better_supabase"."booking_services" to service_role;
create index if not exists "booking_services_tenant_idx" on "better_supabase"."booking_services" ("tenant_id");
drop policy if exists booking_services_read on "better_supabase"."booking_services";
create policy booking_services_read on "better_supabase"."booking_services" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table if not exists "better_supabase"."bookings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "service_id" uuid not null references "better_supabase"."booking_services" ("id") on delete restrict,
  "seat" integer not null default 1 check ("seat" >= 1),
  "during" tstzrange not null check (not isempty("during")),
  "blocked" tstzrange not null,
  "status" text not null default 'hold' check ("status" in ('hold', 'confirmed', 'cancelled')),
  "hold_expires_at" timestamptz,
  "customer_name" text,
  "customer_email" text,
  "customer_user_id" uuid,
  "notes" text,
  "access_hash" text unique,
  "calendar_event_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  check ("blocked" @> "during"),
  check (("status" = 'hold') = ("hold_expires_at" is not null)),
  constraint bookings_no_overlap exclude using gist (
    "resource_id" with =,
    "seat" with =,
    "blocked" with &&
  ) where ("status" <> 'cancelled')
);
create index if not exists bookings_tenant_during_idx on "better_supabase"."bookings" using gist ("tenant_id", "during");
create index if not exists bookings_resource_idx on "better_supabase"."bookings" ("resource_id");
create index if not exists bookings_service_idx on "better_supabase"."bookings" ("service_id");
create index if not exists bookings_hold_idx on "better_supabase"."bookings" ("hold_expires_at") where "status" = 'hold';
alter table "better_supabase"."bookings" enable row level security;
revoke all on "better_supabase"."bookings" from anon, authenticated;
grant select on "better_supabase"."bookings" to authenticated;
grant all on "better_supabase"."bookings" to service_role;
drop policy if exists bookings_read on "better_supabase"."bookings";
create policy bookings_read on "better_supabase"."bookings" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_user_id" = (select auth.uid()));

create or replace function "better_supabase"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function "better_supabase"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = set_booking_availability.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_availability" where "resource_id" = set_booking_availability.resource;
  insert into "better_supabase"."booking_availability" ("tenant_id", "resource_id", "weekday", "starts_at", "ends_at")
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function "better_supabase"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = add_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "better_supabase"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_booking_exception"(exception_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant uuid := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_services" ("tenant_id", "name", "duration", "buffer_before", "buffer_after", "resource_kinds", "step", "min_notice", "hold_for", "active", "reminder_offsets")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'duration' then (v_item ->> 'duration')::interval else null end, case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else interval '0' end, case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else interval '0' end, case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else '{}'::text[] end, case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else null end, case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else interval '0' end, case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else interval '10 minutes' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else '{1440}'::integer[] end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_services" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "duration" = case when v_item ? 'duration' then (v_item ->> 'duration')::interval else "duration" end, "buffer_before" = case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else "buffer_before" end, "buffer_after" = case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else "buffer_after" end, "resource_kinds" = case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else "resource_kinds" end, "step" = case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else "step" end, "min_notice" = case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else "min_notice" end, "hold_for" = case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else "hold_for" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "reminder_offsets" = case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else "reminder_offsets" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it.
-- local_start is the start in tz (default the resource's zone).
create or replace function "better_supabase"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "better_supabase"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = available_slots.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)) or (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false))) then
    raise exception 'not allowed to read bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(available_slots.service, available_slots.range_start, available_slots.range_end, available_slots.tz, available_slots.resource) t), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function "better_supabase"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'expired', "updated_at" = now()
    where bk."status" = 'hold' and bk."hold_expires_at" <= now()
      and (expire_booking_holds_in.resource is null or bk."resource_id" = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk."blocked" && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "better_supabase"."expire_booking_holds"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."expire_booking_holds_in"(null, null)
$$;
revoke execute on function "better_supabase"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds"() to service_role;

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function "better_supabase"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  null;
  if v_status = 'confirmed' then
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$$;
revoke execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function "better_supabase"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = hold_booking.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return "better_supabase"."place_booking"(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
revoke execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function "better_supabase"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$$;
revoke execute on function "better_supabase"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "better_supabase"."confirm_booking"(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(confirm_booking.booking, 'confirmed', null, null)
$$;
revoke execute on function "better_supabase"."confirm_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
revoke execute on function "better_supabase"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_booking"(uuid, text) to authenticated, service_role;

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function "better_supabase"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$$;
revoke execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

-- blocks.bookings.api: entry points for the Data API.
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

create or replace function "api"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_booking_resource"($1, $2) $$;
revoke execute on function "api"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_booking_availability"($1, $2) $$;
revoke execute on function "api"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_booking_exception"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "api"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "api"."delete_booking_exception"(exception_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_booking_exception"($1) $$;
revoke execute on function "api"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "api"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "api"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_booking_service"($1, $2) $$;
revoke execute on function "api"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."booking_slots"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "api"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "api"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."available_slots"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "api"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

create or replace function "api"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_booking_holds_in"($1, $2) $$;
revoke execute on function "api"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "api"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "api"."expire_booking_holds"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_booking_holds"() $$;
revoke execute on function "api"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "api"."expire_booking_holds"() to service_role;

create or replace function "api"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."place_booking"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "api"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

create or replace function "api"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."hold_booking"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "api"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."change_booking"($1, $2, $3, $4) $$;
revoke execute on function "api"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "api"."confirm_booking"(booking uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."confirm_booking"($1) $$;
revoke execute on function "api"."confirm_booking"(uuid) from public, anon;
grant execute on function "api"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_booking"($1, $2) $$;
revoke execute on function "api"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "api"."cancel_booking"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_bookings"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "api"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module-data bookings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module bookings@1 adopt
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
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

create or replace function "better_supabase"."save_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_resource"(uuid, jsonb) to authenticated, service_role;

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function "better_supabase"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = set_booking_availability.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_availability" where "resource_id" = set_booking_availability.resource;
  insert into "better_supabase"."booking_availability" ("tenant_id", "resource_id", "weekday", "starts_at", "ends_at")
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function "better_supabase"."add_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = add_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "better_supabase"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "better_supabase"."add_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_booking_exception"(exception_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."booking_exceptions" where "id" = delete_booking_exception.exception_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant uuid := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_services" ("tenant_id", "name", "duration", "buffer_before", "buffer_after", "resource_kinds", "step", "min_notice", "hold_for", "active", "reminder_offsets")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'duration' then (v_item ->> 'duration')::interval else null end, case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else interval '0' end, case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else interval '0' end, case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else '{}'::text[] end, case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else null end, case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else interval '0' end, case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else interval '10 minutes' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else '{1440}'::integer[] end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_services" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "duration" = case when v_item ? 'duration' then (v_item ->> 'duration')::interval else "duration" end, "buffer_before" = case when v_item ? 'bufferBefore' then (v_item ->> 'bufferBefore')::interval else "buffer_before" end, "buffer_after" = case when v_item ? 'bufferAfter' then (v_item ->> 'bufferAfter')::interval else "buffer_after" end, "resource_kinds" = case when v_item ? 'resourceKinds' then array(select jsonb_array_elements_text(v_item -> 'resourceKinds')) else "resource_kinds" end, "step" = case when v_item ? 'step' then nullif(v_item ->> 'step', '')::interval else "step" end, "min_notice" = case when v_item ? 'minNotice' then (v_item ->> 'minNotice')::interval else "min_notice" end, "hold_for" = case when v_item ? 'holdFor' then (v_item ->> 'holdFor')::interval else "hold_for" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "reminder_offsets" = case when v_item ? 'reminderOffsets' then array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer) else "reminder_offsets" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it.
-- local_start is the start in tz (default the resource's zone).
create or replace function "better_supabase"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "better_supabase"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = available_slots.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)) or (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false))) then
    raise exception 'not allowed to read bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    raise exception 'ask for at most 62 days of slots' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from "better_supabase"."booking_slots"(available_slots.service, available_slots.range_start, available_slots.range_end, available_slots.tz, available_slots.resource) t), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon;
grant execute on function "better_supabase"."available_slots"(uuid, timestamptz, timestamptz, text, uuid) to authenticated, service_role;

-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function "better_supabase"."expire_booking_holds_in"(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'expired', "updated_at" = now()
    where bk."status" = 'hold' and bk."hold_expires_at" <= now()
      and (expire_booking_holds_in.resource is null or bk."resource_id" = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk."blocked" && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds_in"(uuid, tstzrange) to service_role;

create or replace function "better_supabase"."expire_booking_holds"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."expire_booking_holds_in"(null, null)
$$;
revoke execute on function "better_supabase"."expire_booking_holds"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_booking_holds"() to service_role;

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function "better_supabase"."place_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  null;
  if v_status = 'confirmed' then
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$$;
revoke execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."place_booking"(uuid, uuid, timestamptz, jsonb, boolean, uuid) to service_role;

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function "better_supabase"."hold_booking"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = hold_booking.service;
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return "better_supabase"."place_booking"(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
revoke execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."hold_booking"(uuid, uuid, timestamptz, jsonb, boolean) to authenticated, service_role;

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function "better_supabase"."change_booking"(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    
    
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$$;
revoke execute on function "better_supabase"."change_booking"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."change_booking"(uuid, text, text, text) to service_role;

create or replace function "better_supabase"."confirm_booking"(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(confirm_booking.booking, 'confirmed', null, null)
$$;
revoke execute on function "better_supabase"."confirm_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."confirm_booking"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."cancel_booking"(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."change_booking"(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
revoke execute on function "better_supabase"."cancel_booking"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_booking"(uuid, text) to authenticated, service_role;

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function "better_supabase"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$$;
revoke execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_73_bookings.sql
-- better-supabase module: bookings
-- @bs-module-data bookings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('bookings', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
