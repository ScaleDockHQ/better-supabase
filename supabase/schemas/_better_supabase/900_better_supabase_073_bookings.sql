-- better-supabase module: bookings
-- @bsb-block bookings@1 managed
-- @bsb-hash sha256:498127f318fa90fccc3d986034af731bf04c6d15cc4a985c83f794572ddc92ae
-- Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; recurring series book every occurrence; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists btree_gist with schema extensions;
create table "better_supabase"."booking_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_booking_resources_name_check check (length("name") >= 1 and length("name") <= 120),
  "kind" text not null default 'staff',
  "capacity" integer not null default 1 constraint bsb_booking_resources_capacity_check check ("capacity" >= 1 and "capacity" <= 1000),
  "tz" text not null default 'UTC',
  "calendar_id" uuid,
  "host_id" uuid,
  "check_busy" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_resources" enable row level security;
revoke all on "better_supabase"."booking_resources" from public, anon, authenticated;
grant select on "better_supabase"."booking_resources" to authenticated;
grant all on "better_supabase"."booking_resources" to service_role;
create index "booking_resources_tenant_idx" on "better_supabase"."booking_resources" ("tenant_id");
create policy bsb_booking_resources_read on "better_supabase"."booking_resources"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table "better_supabase"."booking_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "weekday" smallint not null constraint bsb_booking_availability_weekday_check check ("weekday" >= 1 and "weekday" <= 7),
  "starts_at" time not null,
  "ends_at" time not null,
  constraint bsb_booking_availability_check check ("ends_at" > "starts_at")
);
create index booking_availability_resource_idx on "better_supabase"."booking_availability" ("resource_id", "weekday");
alter table "better_supabase"."booking_availability" enable row level security;
revoke all on "better_supabase"."booking_availability" from public, anon, authenticated;
grant select on "better_supabase"."booking_availability" to authenticated;
grant all on "better_supabase"."booking_availability" to service_role;
create policy bsb_booking_availability_read on "better_supabase"."booking_availability"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table "better_supabase"."booking_exceptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "during" tstzrange not null constraint bsb_booking_exceptions_during_check check (not isempty("during")),
  "available" boolean not null default false,
  "reason" text
);
create index booking_exceptions_resource_idx on "better_supabase"."booking_exceptions" using gist ("resource_id", "during");
alter table "better_supabase"."booking_exceptions" enable row level security;
revoke all on "better_supabase"."booking_exceptions" from public, anon, authenticated;
grant select on "better_supabase"."booking_exceptions" to authenticated;
grant all on "better_supabase"."booking_exceptions" to service_role;
create policy bsb_booking_exceptions_read on "better_supabase"."booking_exceptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')));
create table "better_supabase"."booking_services" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_booking_services_name_check check (length("name") >= 1 and length("name") <= 120),
  "duration" interval not null constraint bsb_booking_services_duration_check check ("duration" > interval '0'),
  "buffer_before" interval not null default interval '0' constraint bsb_booking_services_buffer_before_check check ("buffer_before" >= interval '0'),
  "buffer_after" interval not null default interval '0' constraint bsb_booking_services_buffer_after_check check ("buffer_after" >= interval '0'),
  "resource_kinds" text[] not null default '{}',
  "step" interval constraint bsb_booking_services_step_check check ("step" > interval '0'),
  "min_notice" interval not null default interval '0',
  "hold_for" interval not null default interval '10 minutes' constraint bsb_booking_services_hold_for_check check ("hold_for" > interval '0'),
  "reminder_offsets" integer[] not null default '{1440}',
  "active" boolean not null default true,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."booking_services" enable row level security;
revoke all on "better_supabase"."booking_services" from public, anon, authenticated;
grant select on "better_supabase"."booking_services" to authenticated;
grant all on "better_supabase"."booking_services" to service_role;
create index "booking_services_tenant_idx" on "better_supabase"."booking_services" ("tenant_id");
create policy bsb_booking_services_read on "better_supabase"."booking_services"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')));
create table "better_supabase"."bookings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "service_id" uuid not null references "better_supabase"."booking_services" ("id") on delete restrict,
  "seat" integer not null default 1 constraint bsb_bookings_seat_check check ("seat" >= 1),
  "during" tstzrange not null constraint bsb_bookings_during_check check (not isempty("during")),
  "blocked" tstzrange not null,
  "status" text not null default 'hold' constraint bsb_bookings_status_check check ("status" in ('hold', 'confirmed', 'cancelled')),
  "hold_expires_at" timestamptz,
  "customer_name" text,
  "customer_email" text,
  "customer_id" uuid,
  "notes" text,
  "access_hash" text unique,
  "calendar_event_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  "archived_at" timestamptz,
  constraint bsb_bookings_check check ("blocked" @> "during"),
  constraint bsb_bookings_check1 check (("status" = 'hold') = ("hold_expires_at" is not null)),
  constraint bookings_no_overlap_excl exclude using gist (
    "resource_id" with =,
    "seat" with =,
    "blocked" with &&
  ) where ("status" <> 'cancelled')
);
create index bookings_tenant_during_idx on "better_supabase"."bookings" using gist ("tenant_id", "during");
create index bookings_resource_idx on "better_supabase"."bookings" ("resource_id");
create index bookings_service_idx on "better_supabase"."bookings" ("service_id");
create index bookings_hold_idx on "better_supabase"."bookings" ("hold_expires_at") where "status" = 'hold';
alter table "better_supabase"."bookings" enable row level security;
revoke all on "better_supabase"."bookings" from public, anon, authenticated;
grant select on "better_supabase"."bookings" to authenticated;
grant all on "better_supabase"."bookings" to service_role;
create policy bsb_bookings_read on "better_supabase"."bookings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_id" = (select auth.uid())) or (("tenant_id")::text, ('booking')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g));

-- A recurring booking: the rule that made it and the occurrences it booked
-- (bookings.series_id). starts_at is the first occurrence; later ones keep its
-- local time in tz, so they move with daylight saving.
create table "better_supabase"."booking_series" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "service_id" uuid not null references "better_supabase"."booking_services" ("id") on delete restrict,
  "resource_id" uuid not null references "better_supabase"."booking_resources" ("id") on delete cascade,
  "rule" jsonb not null constraint bsb_booking_series_rule_check check (jsonb_typeof("rule") = 'object'),
  "starts_at" timestamptz not null,
  "tz" text not null,
  "customer_name" text,
  "customer_email" text,
  "customer_id" uuid,
  "status" text not null default 'active' constraint bsb_booking_series_status_check check ("status" in ('active', 'ended', 'cancelled')),
  "ends_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index "booking_series_tenant_idx" on "better_supabase"."booking_series" ("tenant_id", "starts_at");
create index "booking_series_service_idx" on "better_supabase"."booking_series" ("service_id");
create index "booking_series_resource_idx" on "better_supabase"."booking_series" ("resource_id");
create index "booking_series_customer_idx" on "better_supabase"."booking_series" ("customer_id");
alter table "better_supabase"."booking_series" enable row level security;
revoke all on "better_supabase"."booking_series" from public, anon, authenticated;
grant select on "better_supabase"."booking_series" to authenticated;
grant all on "better_supabase"."booking_series" to service_role;
create policy bsb_booking_series_read on "better_supabase"."booking_series"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_id" = (select auth.uid()));
alter table "better_supabase"."bookings" add column "series_id" uuid references "better_supabase"."booking_series" ("id") on delete set null;
create index bookings_series_idx on "better_supabase"."bookings" ("series_id", "during");

create or replace function "better_supabase"."upsert_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(upsert_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := upsert_booking_resource.tenant;
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
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id", "host_id", "check_busy")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end, case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else null end, case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else false end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end, "host_id" = case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else "host_id" end, "check_busy" = case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else "check_busy" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."upsert_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_booking_resource"(uuid, jsonb) to authenticated, service_role;

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
create or replace function "better_supabase"."create_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
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
  select "tenant_id" into v_tenant from "better_supabase"."booking_resources" where "id" = create_booking_exception.resource;
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if create_booking_exception.ends_at is null or create_booking_exception.starts_at is null or create_booking_exception.ends_at <= create_booking_exception.starts_at then
    raise exception 'an exception needs a start before its end' using errcode = '22023', hint = 'BOOKING_RANGE_INVALID';
  end if;
  insert into "better_supabase"."booking_exceptions" ("tenant_id", "resource_id", "during", "available", "reason")
  values (v_tenant, create_booking_exception.resource, tstzrange(create_booking_exception.starts_at, create_booking_exception.ends_at), coalesce(create_booking_exception.available, false), create_booking_exception.reason)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."create_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "better_supabase"."create_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

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

create or replace function "better_supabase"."upsert_booking_service"(tenant uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(upsert_booking_service.item, '{}'::jsonb);
  v_tenant uuid := upsert_booking_service.tenant;
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
revoke execute on function "better_supabase"."upsert_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_booking_service"(uuid, jsonb) to authenticated, service_role;

-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it. A
-- resource with a host and check_busy also needs the host free in the
-- calendar (events, out of office, focus time, leave) over the slot and its
-- buffers. local_start is the start in tz (default the resource's zone).
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
  v_busy tstzmultirange := '{}'::tstzmultirange;
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
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity, case when rs."check_busy" then rs."host_id" end as host
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
    v_busy := '{}'::tstzmultirange;
    if v_resource.host is not null then
      select coalesce(range_agg(tstzrange(bb.starts_at, bb.ends_at)), '{}'::tstzmultirange) into v_busy
      from "better_supabase"."calendar_busy_blocks"(v_service.tenant, array[v_resource.host], v_floor - v_service.before, booking_slots.range_end + v_service.after) bb
      where bb.starts_at < bb.ends_at and not exists (select 1 from "better_supabase"."bookings" bk where bk."calendar_event_id" = bb.event_id and bk."resource_id" = v_resource.id);
    end if;
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
        if v_free > 0 and not (v_busy && v_block) then
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
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_id", "notes", "access_hash", "created_by")
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
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
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
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at") || jsonb_build_object('accessToken', v_token);
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
    or (change_booking.access_token is null and coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
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
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
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
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
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
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
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
create or replace function "better_supabase"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
    and (list_bookings.include_archived or bk."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_bookings"(uuid, timestamptz, timestamptz, uuid, boolean) to authenticated, service_role;

-- Archives a cancelled booking, or one that has ended: it leaves the lists and keeps its history.
create or replace function "better_supabase"."archive_booking"(booking uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = archive_booking.booking for update;
  if not found or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_booking."archived_at" is not null then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  if v_booking."status" <> 'cancelled' and upper(v_booking."during") > now() then
    raise exception 'only a cancelled booking or one that has ended is archived' using errcode = '55000', hint = 'BOOKING_ACTIVE';
  end if;
  update "better_supabase"."bookings" bk set "archived_at" = now(), "updated_at" = now()
  where bk."id" = v_booking."id" returning * into v_booking;
  perform "better_supabase".emit_event('booking.archived', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_booking"(uuid) to authenticated, service_role;

-- Restores an archived booking to the lists.
create or replace function "better_supabase"."restore_booking"(booking uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = restore_booking.booking for update;
  if not found or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_booking."archived_at" is null then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  update "better_supabase"."bookings" bk set "archived_at" = null, "updated_at" = now()
  where bk."id" = v_booking."id" returning * into v_booking;
  perform "better_supabase".emit_event('booking.restored', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_booking"(uuid) to authenticated, service_role;

-- The tenant's resources, as the caller (the table's policy decides who sees
-- them). Inactive ones are left out unless include_inactive is set.
create or replace function "better_supabase"."list_booking_resources"(tenant uuid, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rs."id", 'name', rs."name", 'kind', rs."kind",
    'capacity', rs."capacity", 'tz', rs."tz", 'active', rs."active",
    'calendarId', rs."calendar_id",
    'hostUserId', rs."host_id"
  ) order by rs."name", rs."id"), '[]'::jsonb)
  from "better_supabase"."booking_resources" rs
  where rs."tenant_id" = list_booking_resources.tenant
    and (list_booking_resources.include_inactive or rs."active")
$$;
revoke execute on function "better_supabase"."list_booking_resources"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_booking_resources"(uuid, boolean) to authenticated, service_role;

-- The tenant's services with their durations as interval text, as the
-- caller. Inactive ones are left out unless include_inactive is set.
create or replace function "better_supabase"."list_booking_services"(tenant uuid, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', sv."id", 'name', sv."name",
    'duration', sv."duration"::text,
    'bufferBefore', sv."buffer_before"::text,
    'bufferAfter', sv."buffer_after"::text,
    'resourceKinds', to_jsonb(sv."resource_kinds"),
    'active', sv."active"
  ) order by sv."name", sv."id"), '[]'::jsonb)
  from "better_supabase"."booking_services" sv
  where sv."tenant_id" = list_booking_services.tenant
    and (list_booking_services.include_inactive or sv."active")
$$;
revoke execute on function "better_supabase"."list_booking_services"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_booking_services"(uuid, boolean) to authenticated, service_role;

-- A customer's bookings, newest first, as the caller: the table's policy shows
-- a tenant's bookings to readers and a customer their own.
create or replace function "better_supabase"."list_bookings_for_customer"(tenant uuid, customer text, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.starts desc, z.id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as item, lower(bk."during") as starts, bk."id" as id
    from "better_supabase"."bookings" bk
    where bk."tenant_id" = list_bookings_for_customer.tenant
      and bk."customer_id"::text = list_bookings_for_customer.customer
      and bk."archived_at" is null
    order by lower(bk."during") desc, bk."id" desc
    limit least(greatest(coalesce(list_bookings_for_customer.page_size, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."list_bookings_for_customer"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_bookings_for_customer"(uuid, text, integer) to authenticated, service_role;

-- The tenant's bookings as a keyset page, the latest start first (ADR 1077).
-- filters is { status, resourceId, serviceId, customerId (each a value or a
-- list), from, to (the first value counts: bookings that overlap the window),
-- archived (true adds archived bookings), search (customer name, email), sort
-- (startsAt, createdAt, customerName), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_bookings"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_bookings.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'resourceId') then
      raise exception 'facet is one of status, resourceId' using errcode = '22023', hint = 'BOOKING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (bk."status"::text)::text when 'resourceId' then (bk."resource_id"::text)::text end) as v
      from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'createdAt', 'customerName') then
    raise exception 'sort is one of startsAt, createdAt, customerName' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during") >= (v_after ->> 0)::timestamptz and ((lower(bk."during") > (v_after ->> 0)::timestamptz) or (lower(bk."during") = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(bk."during") asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during"), bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by lower(bk."during") desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during") >= (v_after ->> 0)::timestamptz and ((lower(bk."during") > (v_after ->> 0)::timestamptz) or (lower(bk."during") = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(bk."during") asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during"), bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by lower(bk."during") desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((bk."created_at")::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (bk."created_at" >= (v_after ->> 0)::timestamptz and ((bk."created_at" > (v_after ->> 0)::timestamptz) or (bk."created_at" = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by bk."created_at" asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((bk."created_at")::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (bk."created_at", bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by bk."created_at" desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'customerName' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(coalesce(bk."customer_name", '')))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(coalesce(bk."customer_name", '')) >= (v_after ->> 0)::text and ((lower(coalesce(bk."customer_name", '')) > (v_after ->> 0)::text) or (lower(coalesce(bk."customer_name", '')) = (v_after ->> 0)::text and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(coalesce(bk."customer_name", '')) asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'customerName' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(coalesce(bk."customer_name", '')))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(coalesce(bk."customer_name", '')), bk."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(coalesce(bk."customer_name", '')) desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_bookings"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_bookings"(uuid, jsonb) to authenticated, service_role;

-- One booking the caller reads, or null.
create or replace function "better_supabase"."get_booking"(booking uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") from "better_supabase"."bookings" bk where bk."id" = get_booking.booking
$$;
revoke execute on function "better_supabase"."get_booking"(uuid) from public, anon;
grant execute on function "better_supabase"."get_booking"(uuid) to authenticated, service_role;

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
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
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
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
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
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
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
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
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
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
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
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
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
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'bookings.public') then null else 30 end,
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

-- The starts of a rule's occurrences from first_start: { freq: daily or
-- weekly, interval, weekdays (1 is Monday, weekly only), count or until }.
-- Each start keeps first_start's local time in tz, expanded by
-- rrule_occurrences (the recurrence module). At most
-- 366 starts, within 730 days.
create or replace function "better_supabase"."booking_series_starts"(rule jsonb, first_start timestamptz, tz text)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_freq text := booking_series_starts.rule ->> 'freq';
  v_interval integer;
  v_days integer[];
  v_count integer;
  v_until timestamptz;
  v_rrule text;
begin
  if jsonb_typeof(booking_series_starts.rule) is distinct from 'object' or v_freq is null or v_freq not in ('daily', 'weekly') then
    raise exception 'rule.freq is daily or weekly' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = booking_series_starts.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  begin
    v_interval := coalesce((booking_series_starts.rule ->> 'interval')::integer, 1);
    v_count := (booking_series_starts.rule ->> 'count')::integer;
    v_until := (booking_series_starts.rule ->> 'until')::timestamptz;
    v_days := array(select jsonb_array_elements_text(coalesce(booking_series_starts.rule -> 'weekdays', '[]'::jsonb))::integer);
  exception when others then
    raise exception 'rule.interval and rule.count are integers, rule.until a timestamp and rule.weekdays a list of 1 to 7' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end;
  if v_interval not between 1 and 52 then
    raise exception 'rule.interval is between 1 and 52' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is null and v_until is null then
    raise exception 'a rule needs count or until' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is not null and v_count not between 1 and 366 then
    raise exception 'rule.count is between 1 and 366' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_until is not null and v_until < booking_series_starts.first_start then
    raise exception 'rule.until is before the first occurrence' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 7) then
    raise exception 'rule.weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  v_rrule := 'FREQ=' || upper(v_freq) || ';INTERVAL=' || v_interval::text;
  if v_freq = 'weekly' and cardinality(v_days) > 0 then
    v_rrule := v_rrule || ';BYDAY=' || (select string_agg((array['MO','TU','WE','TH','FR','SA','SU'])[d], ',' order by d) from (select distinct d from unnest(v_days) d) days);
  end if;
  if v_count is not null then
    v_rrule := v_rrule || ';COUNT=' || v_count::text;
  end if;
  return query select o from better_supabase.rrule_occurrences(v_rrule, booking_series_starts.first_start, booking_series_starts.tz, tstzrange(booking_series_starts.first_start, booking_series_starts.first_start + interval '730 days', '[)')) o
    where v_until is null or o <= v_until
    order by o
    limit 366;
end;
$$;
revoke execute on function "better_supabase"."booking_series_starts"(jsonb, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."booking_series_starts"(jsonb, timestamptz, text) to authenticated, service_role;

-- Books every occurrence of a rule from starts_at, each through place_booking,
-- so each one must be an open slot and the exclusion constraint settles races.
-- A taken occurrence fails the whole series (BOOKING_SERIES_CONFLICT), or is
-- skipped and listed with skip_conflicts. The occurrences are confirmed.
create or replace function "better_supabase"."book_series"(service uuid, resource uuid, starts_at timestamptz, rule jsonb, customer jsonb, skip_conflicts boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(book_series.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
  v_tenant uuid;
  v_tz text;
  v_series "better_supabase"."booking_series"%rowtype;
  v_at timestamptz;
  v_booking jsonb;
  v_booked jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = book_series.service and "active";
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
  select "tz" into v_tz from "better_supabase"."booking_resources" where "id" = book_series.resource and "tenant_id" = v_tenant and "active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_tz := coalesce(nullif(book_series.rule ->> 'tz', ''), v_tz);
  insert into "better_supabase"."booking_series" ("tenant_id", "service_id", "resource_id", "rule", "starts_at", "tz", "customer_name", "customer_email", "customer_id", "created_by")
  values (v_tenant, book_series.service, book_series.resource, book_series.rule - 'tz', book_series.starts_at, v_tz, v_customer ->> 'name', lower(v_customer ->> 'email'), v_user, auth.uid())
  returning * into v_series;
  for v_at in select t from "better_supabase"."booking_series_starts"(book_series.rule, book_series.starts_at, v_tz) t loop
    begin
      v_booking := "better_supabase"."place_booking"(book_series.service, book_series.resource, v_at, v_customer, true, v_user);
      update "better_supabase"."bookings" set "series_id" = v_series."id" where "id" = (v_booking ->> 'id')::uuid;
      v_booked := v_booked || jsonb_build_array((v_booking - 'accessToken') || jsonb_build_object('seriesId', v_series."id"));
    exception when sqlstate '23P01' then
      if not coalesce(book_series.skip_conflicts, false) then
        raise exception 'an occurrence is not an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
      end if;
      v_skipped := v_skipped || jsonb_build_array(v_at);
    end;
  end loop;
  if jsonb_array_length(v_booked) = 0 then
    raise exception 'no occurrence is an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
  end if;
  update "better_supabase"."booking_series" set "ends_at" = ((v_booked -> -1) ->> 'endsAt')::timestamptz where "id" = v_series."id"
  returning * into v_series;
  return jsonb_build_object('series', jsonb_build_object('id', v_series."id", 'organizationId', v_series."tenant_id"::text, 'serviceId', v_series."service_id", 'resourceId', v_series."resource_id", 'rule', v_series."rule", 'startsAt', v_series."starts_at", 'tz', v_series."tz", 'customerName', v_series."customer_name", 'customerEmail', v_series."customer_email", 'customerUserId', v_series."customer_id", 'status', v_series."status", 'endsAt', v_series."ends_at", 'createdAt', v_series."created_at"), 'bookings', v_booked, 'skipped', v_skipped);
end;
$$;
revoke execute on function "better_supabase"."book_series"(uuid, uuid, timestamptz, jsonb, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."book_series"(uuid, uuid, timestamptz, jsonb, jsonb, boolean) to authenticated, service_role;

-- Moves a live booking to starts_at, keeping its id. The booking frees its
-- seat for the check (cancel reason bs:moving), so the new time must be
-- an open slot apart from the booking itself; a taken time puts it back.
create or replace function "better_supabase"."move_booking"(booking uuid, starts_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."bookings"%rowtype;
  v_booking "better_supabase"."bookings"%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from "better_supabase"."bookings" bk where bk."id" = move_booking.booking for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_old."status" = 'cancelled' then
    raise exception 'a cancelled booking can''t move' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  v_booking := v_old;
  if lower(v_old."during") = move_booking.starts_at then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
  end if;
  v_length := upper(v_old."during") - lower(v_old."during");
  v_before := lower(v_old."during") - lower(v_old."blocked");
  v_after := upper(v_old."blocked") - upper(v_old."during");
  update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'bs:moving'
  where bk."id" = v_old."id";
  if not exists (
    select 1 from "better_supabase"."booking_slots"(v_old."service_id", move_booking.starts_at, move_booking.starts_at + v_length, null, v_old."resource_id") t
    where t.starts_at = move_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs where rs."id" = v_old."resource_id";
  for v_seat in 1..v_capacity loop
    begin
      update "better_supabase"."bookings" bk set "status" = v_old."status", "hold_expires_at" = v_old."hold_expires_at", "cancelled_at" = null, "cancel_reason" = null,
        "seat" = v_seat,
        "during" = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        "blocked" = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        "updated_at" = now()
      where bk."id" = v_old."id"
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_booking."status" = 'confirmed' then
    if v_old."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_old."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
  end if;
  perform "better_supabase".emit_event('booking.rescheduled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason", 'archivedAt', v_booking."archived_at");
end;
$$;
revoke execute on function "better_supabase"."move_booking"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."move_booking"(uuid, timestamptz) to service_role;

-- Moves one occurrence, or this one and every later live one in its series
-- by the same amount (scope 'following'), in one transaction.
create or replace function "better_supabase"."reschedule_booking"(booking uuid, starts_at timestamptz, scope text default 'one')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_shift interval;
  v_id uuid;
  v_moved jsonb := '[]'::jsonb;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = reschedule_booking.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if reschedule_booking.scope is null or reschedule_booking.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  if reschedule_booking.scope = 'one' or v_booking."series_id" is null then
    return jsonb_build_array("better_supabase"."move_booking"(v_booking."id", reschedule_booking.starts_at));
  end if;
  v_shift := reschedule_booking.starts_at - lower(v_booking."during");
  -- Later occurrences move first when the shift is positive, so a series never
  -- collides with itself.
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."series_id" = v_booking."series_id" and bk."status" <> 'cancelled'
      and lower(bk."during") >= lower(v_booking."during")
    order by case when v_shift > interval '0' then lower(bk."during") end desc, lower(bk."during")
  loop
    v_moved := v_moved || jsonb_build_array("better_supabase"."move_booking"(v_id, (select lower(x."during") from "better_supabase"."bookings" x where x."id" = v_id) + v_shift));
  end loop;
  return (select jsonb_agg(m order by (m ->> 'startsAt')::timestamptz) from jsonb_array_elements(v_moved) m);
end;
$$;
revoke execute on function "better_supabase"."reschedule_booking"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reschedule_booking"(uuid, timestamptz, text) to authenticated, service_role;

-- Cancels one occurrence, or this one and every later live one in its series
-- (scope 'following'); the series then ends before it, or is cancelled when
-- nothing is left. Returns how many bookings it cancelled.
create or replace function "better_supabase"."cancel_booking_series"(booking uuid, scope text default 'following', reason text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = cancel_booking_series.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if cancel_booking_series.scope is null or cancel_booking_series.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."status" <> 'cancelled'
      and (bk."id" = v_booking."id"
        or (cancel_booking_series.scope = 'following' and bk."series_id" = v_booking."series_id"
          and lower(bk."during") >= lower(v_booking."during")))
    order by lower(bk."during")
  loop
    perform "better_supabase"."change_booking"(v_id, 'cancelled', cancel_booking_series.reason, null);
    v_count := v_count + 1;
  end loop;
  if cancel_booking_series.scope = 'following' and v_booking."series_id" is not null then
    update "better_supabase"."booking_series" sr set
      "status" = case when exists (
        select 1 from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'
      ) then 'ended' else 'cancelled' end,
      "ends_at" = (select max(upper(bk."during")) from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'),
      "updated_at" = now()
    where sr."id" = v_booking."series_id";
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."cancel_booking_series"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."cancel_booking_series"(uuid, text, text) to authenticated, service_role;

-- A series with its occurrences, as the caller: the policies show it to the
-- tenant's readers and to its customer.
create or replace function "better_supabase"."get_booking_series"(series_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', sr."id", 'organizationId', sr."tenant_id"::text, 'serviceId', sr."service_id", 'resourceId', sr."resource_id", 'rule', sr."rule", 'startsAt', sr."starts_at", 'tz', sr."tz", 'customerName', sr."customer_name", 'customerEmail', sr."customer_email", 'customerUserId', sr."customer_id", 'status', sr."status", 'endsAt', sr."ends_at", 'createdAt', sr."created_at") || jsonb_build_object('bookings', coalesce((
    select jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") order by lower(bk."during"))
    from "better_supabase"."bookings" bk where bk."series_id" = sr."id"
  ), '[]'::jsonb))
  from "better_supabase"."booking_series" sr
  where sr."id" = get_booking_series.series_id
$$;
revoke execute on function "better_supabase"."get_booking_series"(uuid) from public, anon;
grant execute on function "better_supabase"."get_booking_series"(uuid) to authenticated, service_role;

-- Books and confirms a slot, then sets the caller's reminder offset_minutes
-- before it, in one transaction. Returns { booking, reminder }.
create or replace function "better_supabase"."book_with_reminder"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, offset_minutes integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_booking jsonb;
  v_reminder jsonb;
begin
  select s."tenant_id" into v_tenant from "better_supabase"."booking_services" s where s."id" = book_with_reminder.service;
  v_booking := "better_supabase"."hold_booking"(book_with_reminder.service, book_with_reminder.resource, book_with_reminder.starts_at, book_with_reminder.customer, true);
  v_reminder := "better_supabase"."upsert_reminder"(
    tenant => v_tenant,
    subject_type => 'booking',
    subject_id => v_booking ->> 'id',
    offset_minutes => book_with_reminder.offset_minutes
  );
  return jsonb_build_object('booking', v_booking, 'reminder', v_reminder);
end;
$$;
revoke execute on function "better_supabase"."book_with_reminder"(uuid, uuid, timestamptz, jsonb, integer) from public, anon;
grant execute on function "better_supabase"."book_with_reminder"(uuid, uuid, timestamptz, jsonb, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."booking_resources" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."booking_resources" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."booking_resources" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."booking_resources" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."booking_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."booking_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."booking_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."booking_availability" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."booking_exceptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."booking_exceptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."booking_exceptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."booking_exceptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."booking_services" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "tenant_id" in (select better_supabase.tenant_ids_with('bookings.create')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."booking_services" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."booking_services" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."booking_services" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."bookings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('bookings.read')) or "customer_id" = (select auth.uid())) or (("tenant_id")::text, ('booking')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."bookings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."bookings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."bookings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create trigger "bsb_search_booking_index"
  after insert or delete on "better_supabase"."bookings"
  for each row execute function "better_supabase"."search_index_row"('booking', 'id');
create trigger "bsb_search_booking_index_u"
  after update of "id", "tenant_id", "customer_name" on "better_supabase"."bookings"
  for each row when (old."id" is distinct from new."id" or old."tenant_id" is distinct from new."tenant_id" or old."customer_name" is distinct from new."customer_name")
  execute function "better_supabase"."search_index_row"('booking', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.bookings deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"booking","event_prefix":"booking","archive_column":"archived_at"}');

-- blocks.bookings.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."upsert_booking_resource"(tenant uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_booking_resource"($1, $2) $$;
revoke execute on function "api"."upsert_booking_resource"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_booking_resource"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_booking_availability"(resource uuid, source jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_booking_availability"($1, $2) $$;
revoke execute on function "api"."set_booking_availability"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_booking_availability"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."create_booking_exception"(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_booking_exception"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) from public, anon;
grant execute on function "api"."create_booking_exception"(uuid, timestamptz, timestamptz, boolean, text) to authenticated, service_role;

create or replace function "api"."delete_booking_exception"(exception_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_booking_exception"($1) $$;
revoke execute on function "api"."delete_booking_exception"(uuid) from public, anon;
grant execute on function "api"."delete_booking_exception"(uuid) to authenticated, service_role;

create or replace function "api"."upsert_booking_service"(tenant uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_booking_service"($1, $2) $$;
revoke execute on function "api"."upsert_booking_service"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_booking_service"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."booking_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."booking_slots"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function "api"."booking_slots"(uuid, timestamptz, timestamptz, text, uuid) to service_role;

create or replace function "api"."available_slots"(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language sql
stable
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

create or replace function "api"."list_bookings"(tenant uuid, range_start timestamptz, range_end timestamptz, resource uuid default null, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_bookings"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_bookings"(uuid, timestamptz, timestamptz, uuid, boolean) from public, anon;
grant execute on function "api"."list_bookings"(uuid, timestamptz, timestamptz, uuid, boolean) to authenticated, service_role;

create or replace function "api"."archive_booking"(booking uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_booking"($1) $$;
revoke execute on function "api"."archive_booking"(uuid) from public, anon;
grant execute on function "api"."archive_booking"(uuid) to authenticated, service_role;

create or replace function "api"."restore_booking"(booking uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_booking"($1) $$;
revoke execute on function "api"."restore_booking"(uuid) from public, anon;
grant execute on function "api"."restore_booking"(uuid) to authenticated, service_role;

create or replace function "api"."list_booking_resources"(tenant uuid, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_booking_resources"($1, $2) $$;
revoke execute on function "api"."list_booking_resources"(uuid, boolean) from public, anon;
grant execute on function "api"."list_booking_resources"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_booking_services"(tenant uuid, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_booking_services"($1, $2) $$;
revoke execute on function "api"."list_booking_services"(uuid, boolean) from public, anon;
grant execute on function "api"."list_booking_services"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_bookings_for_customer"(tenant uuid, customer text, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_bookings_for_customer"($1, $2, $3) $$;
revoke execute on function "api"."list_bookings_for_customer"(uuid, text, integer) from public, anon;
grant execute on function "api"."list_bookings_for_customer"(uuid, text, integer) to authenticated, service_role;

create or replace function "api"."page_bookings"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_bookings"($1, $2) $$;
revoke execute on function "api"."page_bookings"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_bookings"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_booking"(booking uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_booking"($1) $$;
revoke execute on function "api"."get_booking"(uuid) from public, anon;
grant execute on function "api"."get_booking"(uuid) to authenticated, service_role;

create or replace function "api"."public_booking_service"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_booking_service"($1) $$;
revoke execute on function "api"."public_booking_service"(text) from public;
grant execute on function "api"."public_booking_service"(text) to anon, authenticated, service_role;

create or replace function "api"."public_available_slots"(token text, range_start timestamptz, range_end timestamptz, tz text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_available_slots"($1, $2, $3, $4) $$;
revoke execute on function "api"."public_available_slots"(text, timestamptz, timestamptz, text) from public;
grant execute on function "api"."public_available_slots"(text, timestamptz, timestamptz, text) to anon, authenticated, service_role;

create or replace function "api"."public_hold_booking"(token text, resource uuid, starts_at timestamptz, customer jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_hold_booking"($1, $2, $3, $4) $$;
revoke execute on function "api"."public_hold_booking"(text, uuid, timestamptz, jsonb) from public;
grant execute on function "api"."public_hold_booking"(text, uuid, timestamptz, jsonb) to anon, authenticated, service_role;

create or replace function "api"."public_change_booking"(booking uuid, access_token text, to_status text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_change_booking"($1, $2, $3) $$;
revoke execute on function "api"."public_change_booking"(uuid, text, text) from public;
grant execute on function "api"."public_change_booking"(uuid, text, text) to anon, authenticated, service_role;

create or replace function "api"."booking_series_starts"(rule jsonb, first_start timestamptz, tz text)
returns setof timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."booking_series_starts"($1, $2, $3) $$;
revoke execute on function "api"."booking_series_starts"(jsonb, timestamptz, text) from public, anon;
grant execute on function "api"."booking_series_starts"(jsonb, timestamptz, text) to authenticated, service_role;

create or replace function "api"."book_series"(service uuid, resource uuid, starts_at timestamptz, rule jsonb, customer jsonb, skip_conflicts boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."book_series"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."book_series"(uuid, uuid, timestamptz, jsonb, jsonb, boolean) from public, anon;
grant execute on function "api"."book_series"(uuid, uuid, timestamptz, jsonb, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."move_booking"(booking uuid, starts_at timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."move_booking"($1, $2) $$;
revoke execute on function "api"."move_booking"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "api"."move_booking"(uuid, timestamptz) to service_role;

create or replace function "api"."reschedule_booking"(booking uuid, starts_at timestamptz, scope text default 'one')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reschedule_booking"($1, $2, $3) $$;
revoke execute on function "api"."reschedule_booking"(uuid, timestamptz, text) from public, anon;
grant execute on function "api"."reschedule_booking"(uuid, timestamptz, text) to authenticated, service_role;

create or replace function "api"."cancel_booking_series"(booking uuid, scope text default 'following', reason text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_booking_series"($1, $2, $3) $$;
revoke execute on function "api"."cancel_booking_series"(uuid, text, text) from public, anon;
grant execute on function "api"."cancel_booking_series"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_booking_series"(series_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_booking_series"($1) $$;
revoke execute on function "api"."get_booking_series"(uuid) from public, anon;
grant execute on function "api"."get_booking_series"(uuid) to authenticated, service_role;

create or replace function "api"."book_with_reminder"(service uuid, resource uuid, starts_at timestamptz, customer jsonb, offset_minutes integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."book_with_reminder"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."book_with_reminder"(uuid, uuid, timestamptz, jsonb, integer) from public, anon;
grant execute on function "api"."book_with_reminder"(uuid, uuid, timestamptz, jsonb, integer) to authenticated, service_role;
