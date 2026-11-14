-- ==== schema supabase/schemas/900_better_supabase_123_dispatch.sql
-- better-supabase module: dispatch
-- @bsb-block dispatch@1 managed
-- @bsb-hash sha256:04215a8cd818640ead3eb35ecdae509e9a0068c4883ecd3b695cc771a65f6966
-- Field service work orders at asset locations: a schedule board of technicians' slots, a status lifecycle from scheduled to done, day routes with ordered stops, and the parts each job used, linked to assets or inventory when those blocks are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Dispatch: work orders at asset locations, scheduled into technicians'
-- slots on a board, worked through a status lifecycle, with day routes and
-- the parts each job used.

-- Work orders: a job at a place (an asset location or an address), for an
-- asset or a record, scheduled into a technician's slot and worked through
-- en route, on site and done.
create table "better_supabase"."work_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_work_orders_title_check check (length("title") >= 1 and length("title") <= 200),
  "description" text constraint bsb_work_orders_description_check check ("description" is null or length("description") <= 10000),
  "priority" text not null default 'normal' constraint bsb_work_orders_priority_check check ("priority" in ('low', 'normal', 'high', 'urgent')),
  "status" text not null default 'unscheduled' constraint bsb_work_orders_status_check check ("status" in ('unscheduled', 'scheduled', 'en_route', 'on_site', 'done', 'cancelled')),
  "technician_id" uuid references auth.users (id) on delete set null,
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "location_id" uuid,
  "asset_id" uuid,
  "booking_id" uuid,
  "subject_type" text constraint bsb_work_orders_subject_type_check check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_work_orders_subject_id_check check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "address" text constraint bsb_work_orders_address_check check ("address" is null or length("address") >= 1 and length("address") <= 500),
  "en_route_at" timestamptz,
  "arrived_at" timestamptz,
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_work_orders_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "completion_note" text constraint bsb_work_orders_completion_note_check check ("completion_note" is null or length("completion_note") <= 10000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_work_orders_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_work_orders_check1 check (("starts_at" is null) = ("ends_at" is null)),
  constraint bsb_work_orders_check2 check ("ends_at" is null or "ends_at" > "starts_at"),
  constraint bsb_work_orders_check3 check ("status" not in ('scheduled', 'en_route', 'on_site') or ("technician_id" is not null and "starts_at" is not null))
);
create index "work_orders_tenant_idx" on "better_supabase"."work_orders" ("tenant_id", "created_at" desc, "id" desc);
create index "work_orders_slot_idx" on "better_supabase"."work_orders" ("technician_id", "starts_at") where "starts_at" is not null;
create index "work_orders_board_idx" on "better_supabase"."work_orders" ("tenant_id", "starts_at") where "starts_at" is not null;
create index "work_orders_backlog_idx" on "better_supabase"."work_orders" ("tenant_id", "created_at") where "status" = 'unscheduled';
create index "work_orders_location_idx" on "better_supabase"."work_orders" ("location_id");
create index "work_orders_asset_idx" on "better_supabase"."work_orders" ("asset_id");
create index "work_orders_booking_idx" on "better_supabase"."work_orders" ("booking_id");
create index "work_orders_subject_idx" on "better_supabase"."work_orders" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."work_orders" enable row level security;
revoke all on "better_supabase"."work_orders" from public, anon, authenticated;
grant select on "better_supabase"."work_orders" to authenticated;
grant all on "better_supabase"."work_orders" to service_role;
create policy bsb_work_orders_read on "better_supabase"."work_orders"
  for select to authenticated
  using ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
-- A technician's plan for one day: the work orders in the order they drive to
-- them.
create table "better_supabase"."dispatch_routes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "technician_id" uuid not null references auth.users (id) on delete cascade,
  "route_date" date not null,
  "planned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "technician_id", "route_date")
);
create index "dispatch_routes_technician_idx" on "better_supabase"."dispatch_routes" ("technician_id", "route_date");
alter table "better_supabase"."dispatch_routes" enable row level security;
revoke all on "better_supabase"."dispatch_routes" from public, anon, authenticated;
grant select on "better_supabase"."dispatch_routes" to authenticated;
grant all on "better_supabase"."dispatch_routes" to service_role;
create policy bsb_dispatch_routes_read on "better_supabase"."dispatch_routes"
  for select to authenticated
  using ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
create table "better_supabase"."dispatch_route_stops" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "route_id" uuid not null references "better_supabase"."dispatch_routes" ("id") on delete cascade,
  "work_order_id" uuid not null references "better_supabase"."work_orders" ("id") on delete cascade,
  "position" integer not null constraint bsb_dispatch_route_stops_position_check check ("position" >= 1),
  unique ("route_id", "position"),
  unique ("route_id", "work_order_id")
);
create index "dispatch_route_stops_job_idx" on "better_supabase"."dispatch_route_stops" ("work_order_id");
alter table "better_supabase"."dispatch_route_stops" enable row level security;
revoke all on "better_supabase"."dispatch_route_stops" from public, anon, authenticated;
grant select on "better_supabase"."dispatch_route_stops" to authenticated;
grant all on "better_supabase"."dispatch_route_stops" to service_role;
create policy bsb_dispatch_route_stops_read on "better_supabase"."dispatch_route_stops"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
-- The parts a job used: free text, or an asset, or a catalog variant taken
-- from an inventory location.
create table "better_supabase"."work_order_parts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_order_id" uuid not null references "better_supabase"."work_orders" ("id") on delete cascade,
  "name" text not null constraint bsb_work_order_parts_name_check check (length("name") >= 1 and length("name") <= 200),
  "quantity" numeric(14, 3) not null constraint bsb_work_order_parts_quantity_check check ("quantity" > 0),
  "unit" text constraint bsb_work_order_parts_unit_check check ("unit" is null or length("unit") >= 1 and length("unit") <= 20),
  "asset_id" uuid,
  "variant_id" uuid,
  "location_id" uuid,
  "recorded_by" uuid,
  "created_at" timestamptz not null default now()
);
create index "work_order_parts_job_idx" on "better_supabase"."work_order_parts" ("work_order_id", "created_at");
create index "work_order_parts_asset_idx" on "better_supabase"."work_order_parts" ("asset_id");
create index "work_order_parts_variant_idx" on "better_supabase"."work_order_parts" ("variant_id");
create index "work_order_parts_location_idx" on "better_supabase"."work_order_parts" ("location_id");
alter table "better_supabase"."work_order_parts" enable row level security;
revoke all on "better_supabase"."work_order_parts" from public, anon, authenticated;
grant select on "better_supabase"."work_order_parts" to authenticated;
grant all on "better_supabase"."work_order_parts" to service_role;
create policy bsb_work_order_parts_read on "better_supabase"."work_order_parts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
-- Creates a work order in tenant. With a technician and starts_at (or a
-- booking to take the slot from) it is scheduled at once; otherwise it waits
-- in the backlog. ends_at defaults to starts_at plus the default duration.
create or replace function "better_supabase"."create_work_order"(tenant uuid, title text, description text default null, priority text default 'normal', location_id uuid default null, asset_id uuid default null, booking_id uuid default null, subject_type text default null, subject_id text default null, address text default null, technician uuid default null, starts_at timestamptz default null, ends_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_starts timestamptz := create_work_order.starts_at;
  v_ends timestamptz := create_work_order.ends_at;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_work_order.tenant, 'dispatch.manage'), false)) then
    raise exception 'not allowed to manage work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if (create_work_order.subject_type is null) <> (create_work_order.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'DISPATCH_SUBJECT_INVALID';
  end if;
  if create_work_order.subject_type is not null
    and null::text is distinct from create_work_order.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_SUBJECT_NOT_FOUND';
  end if;
  if coalesce(create_work_order.location_id, create_work_order.asset_id) is not null then
    raise exception 'install the assets block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_ASSETS_MISSING';
  end if;
  if create_work_order.booking_id is not null then
    raise exception 'install the bookings block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_BOOKINGS_MISSING';
  end if;
  if v_starts is not null then
    if create_work_order.technician is null then
      raise exception 'a scheduled work order needs a technician' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_REQUIRED';
    end if;
    v_ends := coalesce(v_ends, v_starts + '1 hour'::interval);
  if not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  if v_ends <= v_starts then
    raise exception 'a slot ends after it starts' using errcode = '22023', hint = 'DISPATCH_SLOT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:dispatch:' || create_work_order.technician::text, 0));
  if exists (
    select 1 from "better_supabase"."work_orders" o
    where o."tenant_id" = create_work_order.tenant and o."technician_id" = create_work_order.technician
      and o."id" is distinct from null::uuid
      and o."status" in ('scheduled', 'en_route', 'on_site')
      and o."starts_at" < v_ends and o."ends_at" > v_starts
  ) then
    raise exception 'the technician already has a work order in that slot' using errcode = '23P01', hint = 'DISPATCH_SLOT_TAKEN';
  end if;
  elsif create_work_order.technician is not null
    and not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  begin
    insert into "better_supabase"."work_orders" ("tenant_id", "title", "description", "priority", "status", "technician_id", "starts_at", "ends_at", "location_id", "asset_id", "booking_id", "subject_type", "subject_id", "address", "created_by")
    values (create_work_order.tenant, btrim(create_work_order.title), create_work_order.description, coalesce(create_work_order.priority, 'normal'),
      case when v_starts is null then 'unscheduled' else 'scheduled' end, create_work_order.technician, v_starts, v_ends,
      create_work_order.location_id, create_work_order.asset_id, create_work_order.booking_id,
      create_work_order.subject_type, create_work_order.subject_id, nullif(btrim(create_work_order.address), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation then
    raise exception 'a work order needs a title of 1 to 200 characters and a known priority' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end;
  null;
  if v_row."status" = 'scheduled' then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) to authenticated, service_role;
-- Changes a work order's title, description, priority or place; null keeps a
-- value.
create or replace function "better_supabase"."update_work_order"(work_order_id uuid, title text default null, description text default null, priority text default null, location_id uuid default null, asset_id uuid default null, address text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_orders" x where x."id" = update_work_order.work_order_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if coalesce(update_work_order.location_id, update_work_order.asset_id) is not null then
    raise exception 'install the assets block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_ASSETS_MISSING';
  end if;
  begin
    update "better_supabase"."work_orders" x set
      "title" = coalesce(btrim(update_work_order.title), x."title"),
      "description" = coalesce(update_work_order.description, x."description"),
      "priority" = coalesce(update_work_order.priority, x."priority"),
      "location_id" = coalesce(update_work_order.location_id, x."location_id"),
      "asset_id" = coalesce(update_work_order.asset_id, x."asset_id"),
      "address" = coalesce(nullif(btrim(update_work_order.address), ''), x."address"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'a work order needs a title of 1 to 200 characters and a known priority' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_work_order"(uuid, text, text, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."update_work_order"(uuid, text, text, text, uuid, uuid, text) to authenticated, service_role;

-- Puts a work order in a technician's slot, or moves it to another one.
-- ends_at defaults to starts_at plus the default duration.
create or replace function "better_supabase"."schedule_work_order"(work_order_id uuid, technician uuid, starts_at timestamptz, ends_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_ends timestamptz := coalesce(schedule_work_order.ends_at, schedule_work_order.starts_at + '1 hour'::interval);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_orders" x where x."id" = schedule_work_order.work_order_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if v_row."status" not in ('unscheduled', 'scheduled') then
    raise exception 'only a work order in the backlog or not started yet can be scheduled' using errcode = '55000', hint = 'DISPATCH_STATUS_INVALID';
  end if;
  if schedule_work_order.technician is null or schedule_work_order.starts_at is null then
    raise exception 'a scheduled work order needs a technician and a start' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_REQUIRED';
  end if;
  if not coalesce(better_supabase.can_user(schedule_work_order.technician, 'tenant', v_row."tenant_id", 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  if v_ends <= schedule_work_order.starts_at then
    raise exception 'a slot ends after it starts' using errcode = '22023', hint = 'DISPATCH_SLOT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:dispatch:' || schedule_work_order.technician::text, 0));
  if exists (
    select 1 from "better_supabase"."work_orders" o
    where o."tenant_id" = v_row."tenant_id" and o."technician_id" = schedule_work_order.technician
      and o."id" is distinct from v_row."id"
      and o."status" in ('scheduled', 'en_route', 'on_site')
      and o."starts_at" < v_ends and o."ends_at" > schedule_work_order.starts_at
  ) then
    raise exception 'the technician already has a work order in that slot' using errcode = '23P01', hint = 'DISPATCH_SLOT_TAKEN';
  end if;
  if v_row."technician_id" is distinct from schedule_work_order.technician then
    delete from "better_supabase"."dispatch_route_stops" st where st."work_order_id" = v_row."id";
  end if;
  update "better_supabase"."work_orders" x set "status" = 'scheduled', "technician_id" = schedule_work_order.technician,
    "starts_at" = schedule_work_order.starts_at, "ends_at" = v_ends, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_work_order"(uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."schedule_work_order"(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;

-- Takes a work order that hasn't started off the schedule, back to the
-- backlog, and off any route.
create or replace function "better_supabase"."unschedule_work_order"(work_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_technician uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_orders" x where x."id" = unschedule_work_order.work_order_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if v_row."status" = 'unscheduled' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if v_row."status" <> 'scheduled' then
    raise exception 'only a work order that hasn''t started can go back to the backlog' using errcode = '55000', hint = 'DISPATCH_STATUS_INVALID';
  end if;
  v_technician := v_row."technician_id";
  delete from "better_supabase"."dispatch_route_stops" st where st."work_order_id" = v_row."id";
  update "better_supabase"."work_orders" x set "status" = 'unscheduled', "technician_id" = null, "starts_at" = null,
    "ends_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unschedule_work_order"(uuid) from public, anon;
grant execute on function "better_supabase"."unschedule_work_order"(uuid) to authenticated, service_role;

-- Moves a work order along: scheduled to en_route, en_route or scheduled to
-- on_site, on_site to done, and anything not finished to cancelled. The
-- technician moves their own work orders; only a dispatcher cancels. note is
-- the completion note for done and the reason for cancelled.
create or replace function "better_supabase"."set_work_order_status"(work_order_id uuid, status text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_from text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_orders" x where x."id" = set_work_order_status.work_order_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) or (coalesce(v_row."technician_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.work'), false))) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  v_from := v_row."status";
  if set_work_order_status.status = v_from then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if not (
    (set_work_order_status.status = 'en_route' and v_from = 'scheduled')
    or (set_work_order_status.status = 'on_site' and v_from in ('scheduled', 'en_route'))
    or (set_work_order_status.status = 'done' and v_from = 'on_site')
    or (set_work_order_status.status = 'cancelled' and v_from in ('unscheduled', 'scheduled', 'en_route', 'on_site'))
  ) then
    raise exception 'a work order can''t move to that status from where it is' using errcode = '55000', hint = 'DISPATCH_TRANSITION_INVALID';
  end if;
  if set_work_order_status.status = 'cancelled' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) then
    raise exception 'only a dispatcher can cancel a work order' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  update "better_supabase"."work_orders" x set
    "status" = set_work_order_status.status,
    "en_route_at" = case when set_work_order_status.status = 'en_route' then now() else x."en_route_at" end,
    "arrived_at" = case when set_work_order_status.status = 'on_site' then now() else x."arrived_at" end,
    "completed_at" = case when set_work_order_status.status = 'done' then now() else x."completed_at" end,
    "completion_note" = case when set_work_order_status.status = 'done' then set_work_order_status.note else x."completion_note" end,
    "cancelled_at" = case when set_work_order_status.status = 'cancelled' then now() else x."cancelled_at" end,
    "cancel_reason" = case when set_work_order_status.status = 'cancelled' then set_work_order_status.note else x."cancel_reason" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_work_order_status"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_work_order_status"(uuid, text, text) to authenticated, service_role;

-- One work order, for a dispatcher, a reader or its technician; null
-- otherwise.
create or replace function "better_supabase"."get_work_order"(work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
begin
  select * into v_row from "better_supabase"."work_orders" x where x."id" = get_work_order.work_order_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)) or ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) or (coalesce(v_row."technician_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.work'), false)))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_work_order"(uuid) from public, anon;
grant execute on function "better_supabase"."get_work_order"(uuid) to authenticated, service_role;

-- A tenant's work orders, newest first, filtered by status, technician,
-- record or a window their slot overlaps.
create or replace function "better_supabase"."list_work_orders"(tenant uuid, status text default null, technician uuid default null, subject_type text default null, subject_id text default null, from_at timestamptz default null, until_at timestamptz default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_work_orders.tenant, 'dispatch.read'), false)) then
    raise exception 'not allowed to read work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
      from "better_supabase"."work_orders" x
      where x."tenant_id" = list_work_orders.tenant
        and (list_work_orders.status is null or x."status" = list_work_orders.status)
        and (list_work_orders.technician is null or x."technician_id" = list_work_orders.technician)
        and (list_work_orders.subject_type is null or (x."subject_type" = list_work_orders.subject_type and x."subject_id" = list_work_orders.subject_id))
        and (list_work_orders.from_at is null or x."ends_at" > list_work_orders.from_at)
        and (list_work_orders.until_at is null or x."starts_at" < list_work_orders.until_at)
        and (list_work_orders.before is null or x."created_at" < list_work_orders.before)
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_work_orders.page_size, 50), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_work_orders"(uuid, text, uuid, text, text, timestamptz, timestamptz, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_work_orders"(uuid, text, uuid, text, text, timestamptz, timestamptz, timestamptz, integer) to authenticated, service_role;

-- A tenant's work orders as a keyset page (ADR 0749, 0949). filters is { status,
-- priority, technicianId, assetId, subjectType, subjectId (each a value or a
-- list of them), from (slot ends after), until (slot starts before), search
-- (title), sort, direction, facet, count, limit, after, offset, paged, total,
-- totalCap }. Needs dispatch.read.
create or replace function "better_supabase"."page_work_orders"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_work_orders.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_from timestamptz;
  v_until timestamptz;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_work_orders.tenant, 'dispatch.read'), false)) then
    raise exception 'not allowed to read work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then v_filters -> 'technicianId' when jsonb_typeof(v_filters -> 'technicianId') in ('string', 'number') then jsonb_build_array(v_filters -> 'technicianId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'assetId') = 'array' then v_filters -> 'assetId' when jsonb_typeof(v_filters -> 'assetId') in ('string', 'number') then jsonb_build_array(v_filters -> 'assetId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'technicianId and assetId must be uuids' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  begin
    v_from := nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz;
    v_until := nullif(coalesce(v_filters #>> '{until,0}', v_filters ->> 'until'), '')::timestamptz;
  exception when others then
    raise exception 'from and until must be timestamps' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'priority') then
      raise exception 'facet is one of status, priority' using errcode = '22023', hint = 'DISPATCH_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'priority' then (x."priority")::text end) as v
      from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'startsAt', 'title') then
    raise exception 'sort is one of createdAt, startsAt, title' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_orders" x
      where x."tenant_id" = page_work_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'technicianId' is not null and jsonb_typeof(v_filters -> 'technicianId') <> 'null' and not (jsonb_typeof(v_filters -> 'technicianId') = 'array' and jsonb_array_length(v_filters -> 'technicianId') = 0)) or x."technician_id" = any((case when jsonb_typeof(v_filters -> 'technicianId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'technicianId')) else array[v_filters ->> 'technicianId'] end)::uuid[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (v_from is null or x."ends_at" > v_from)
        and (v_until is null or x."starts_at" < v_until)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_work_orders"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_work_orders"(uuid, jsonb) to authenticated, service_role;

-- The schedule board from from_date to to_date (at most 31 days, in the
-- block's time zone): the scheduled work orders with their day, the
-- technicians (the ones passed, else the ones with work orders), and the
-- backlog by priority.
create or replace function "better_supabase"."dispatch_board"(tenant uuid, from_date date, to_date date, technicians uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_from timestamptz;
  v_until timestamptz;
  v_orders jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', dispatch_board.tenant, 'dispatch.read'), false)) then
    raise exception 'not allowed to read work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if dispatch_board.from_date is null or dispatch_board.to_date is null
    or dispatch_board.to_date < dispatch_board.from_date
    or dispatch_board.to_date - dispatch_board.from_date >= 31 then
    raise exception 'the board spans 1 to 31 days' using errcode = '22023', hint = 'DISPATCH_RANGE_INVALID';
  end if;
  v_from := (dispatch_board.from_date::timestamp at time zone 'UTC');
  v_until := ((dispatch_board.to_date + 1)::timestamp at time zone 'UTC');
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."starts_at", x."id"), '[]'::jsonb) into v_orders
    from "better_supabase"."work_orders" x
    where x."tenant_id" = dispatch_board.tenant
      and x."starts_at" < v_until and x."ends_at" > v_from
      and x."status" <> 'cancelled'
      and (dispatch_board.technicians is null or x."technician_id" = any (dispatch_board.technicians));
  return jsonb_build_object(
    'from', dispatch_board.from_date,
    'to', dispatch_board.to_date,
    'timeZone', 'UTC',
    'technicianIds', coalesce(
      to_jsonb(dispatch_board.technicians),
      (select coalesce(jsonb_agg(distinct e ->> 'technicianId'), '[]'::jsonb) from jsonb_array_elements(v_orders) e where e ->> 'technicianId' is not null)
    ),
    'scheduled', v_orders,
    'backlog', (
      select coalesce(jsonb_agg(z.item order by z.rank desc, z.created, z.id), '[]'::jsonb)
      from (
        select jsonb_build_object('id', b."id", 'organizationId', b."tenant_id"::text, 'title', b."title", 'description', b."description", 'priority', b."priority", 'status', b."status", 'technicianId', b."technician_id", 'startsAt', b."starts_at", 'endsAt', b."ends_at", 'day', (b."starts_at" at time zone 'UTC')::date, 'locationId', b."location_id", 'assetId', b."asset_id", 'bookingId', b."booking_id", 'subjectType', b."subject_type", 'subjectId', b."subject_id", 'address', b."address", 'enRouteAt', b."en_route_at", 'arrivedAt', b."arrived_at", 'completedAt', b."completed_at", 'cancelledAt', b."cancelled_at", 'cancelReason', b."cancel_reason", 'completionNote', b."completion_note", 'createdBy', b."created_by", 'createdAt', b."created_at", 'updatedAt', b."updated_at") as item, array_position(array['low', 'normal', 'high', 'urgent'], b."priority") as rank,
          b."created_at" as created, b."id" as id
        from "better_supabase"."work_orders" b
        where b."tenant_id" = dispatch_board.tenant and b."status" = 'unscheduled'
        order by array_position(array['low', 'normal', 'high', 'urgent'], b."priority") desc, b."created_at", b."id"
        limit 200
      ) z
    )
  );
end;
$$;
revoke execute on function "better_supabase"."dispatch_board"(uuid, date, date, uuid[]) from public, anon;
grant execute on function "better_supabase"."dispatch_board"(uuid, date, date, uuid[]) to authenticated, service_role;

-- A technician's day plan: the stops of their route in order, then the other
-- work orders of the day by start. technician defaults to the caller.
create or replace function "better_supabase"."technician_day"(tenant uuid, day date, technician uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_technician uuid := coalesce(technician_day.technician, auth.uid());
  v_route "better_supabase"."dispatch_routes"%rowtype;
begin
  if v_technician is null or not (
    (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', technician_day.tenant, 'dispatch.read'), false))
    or (coalesce(v_technician = auth.uid(), false) and coalesce(better_supabase.can('tenant', technician_day.tenant, 'dispatch.work'), false))
  ) then
    raise exception 'not allowed to read this technician''s day' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  select * into v_route from "better_supabase"."dispatch_routes" rt
    where rt."tenant_id" = technician_day.tenant and rt."technician_id" = v_technician and rt."route_date" = technician_day.day;
  return jsonb_build_object(
    'technicianId', v_technician,
    'date', technician_day.day,
    'routeId', v_route."id",
    'stops', (
      select coalesce(jsonb_agg(jsonb_build_object('position', z.position, 'workOrder', z.item) order by z.position), '[]'::jsonb)
      from (
        select row_number() over (order by y.planned nulls last, y.starts, y.id) as position, y.item
        from (
          select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'title', x."title", 'description', x."description", 'priority', x."priority", 'status', x."status", 'technicianId', x."technician_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'day', (x."starts_at" at time zone 'UTC')::date, 'locationId', x."location_id", 'assetId', x."asset_id", 'bookingId', x."booking_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'enRouteAt', x."en_route_at", 'arrivedAt', x."arrived_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'completionNote', x."completion_note", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, st."position" as planned, x."starts_at" as starts, x."id" as id
          from "better_supabase"."work_orders" x
          left join "better_supabase"."dispatch_route_stops" st on st."work_order_id" = x."id" and st."route_id" = v_route."id"
          where x."tenant_id" = technician_day.tenant
            and (st."id" is not null or (
              x."technician_id" = v_technician and x."status" <> 'cancelled'
              and x."starts_at" >= (technician_day.day::timestamp at time zone 'UTC')
              and x."starts_at" < ((technician_day.day + 1)::timestamp at time zone 'UTC')
            ))
        ) y
      ) z
    )
  );
end;
$$;
revoke execute on function "better_supabase"."technician_day"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."technician_day"(uuid, date, uuid) to authenticated, service_role;

-- Sets the order a technician drives to work orders on a day. Each work order
-- must be theirs; the list replaces the route's stops. A dispatcher plans any
-- route, a technician their own.
create or replace function "better_supabase"."plan_dispatch_route"(tenant uuid, technician uuid, route_date date, work_orders uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_route "better_supabase"."dispatch_routes"%rowtype;
  v_count integer := coalesce(cardinality(plan_dispatch_route.work_orders), 0);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if plan_dispatch_route.technician is null or not (
    (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', plan_dispatch_route.tenant, 'dispatch.manage'), false))
    or (coalesce(plan_dispatch_route.technician = auth.uid(), false) and coalesce(better_supabase.can('tenant', plan_dispatch_route.tenant, 'dispatch.work'), false))
  ) then
    raise exception 'not allowed to plan this technician''s route' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if plan_dispatch_route.route_date is null or v_count > 100
    or v_count <> (select count(distinct u) from unnest(plan_dispatch_route.work_orders) u where u is not null) then
    raise exception 'a route lists up to 100 different work orders for a day' using errcode = '22023', hint = 'DISPATCH_ROUTE_INVALID';
  end if;
  if v_count <> (
    select count(*) from "better_supabase"."work_orders" x
    where x."id" = any (plan_dispatch_route.work_orders)
      and x."tenant_id" = plan_dispatch_route.tenant
      and x."technician_id" = plan_dispatch_route.technician
      and x."status" <> 'cancelled'
  ) then
    raise exception 'every stop must be a live work order of this technician' using errcode = '22023', hint = 'DISPATCH_ROUTE_INVALID';
  end if;
  insert into "better_supabase"."dispatch_routes" ("tenant_id", "technician_id", "route_date", "planned_by")
  values (plan_dispatch_route.tenant, plan_dispatch_route.technician, plan_dispatch_route.route_date, auth.uid())
  on conflict ("tenant_id", "technician_id", "route_date")
    do update set "planned_by" = excluded."planned_by", "updated_at" = now()
  returning * into v_route;
  delete from "better_supabase"."dispatch_route_stops" st where st."route_id" = v_route."id";
  insert into "better_supabase"."dispatch_route_stops" ("tenant_id", "route_id", "work_order_id", "position")
  select plan_dispatch_route.tenant, v_route."id", u.id, u.position
  from unnest(plan_dispatch_route.work_orders) with ordinality as u(id, position);
  null;
  return jsonb_build_object('id', v_route."id", 'organizationId', v_route."tenant_id"::text,
    'technicianId', v_route."technician_id", 'routeDate', v_route."route_date",
    'stops', coalesce(to_jsonb(plan_dispatch_route.work_orders), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."plan_dispatch_route"(uuid, uuid, date, uuid[]) from public, anon;
grant execute on function "better_supabase"."plan_dispatch_route"(uuid, uuid, date, uuid[]) to authenticated, service_role;

-- Records a part a work order used: free text, an asset, or a catalog variant
-- from an inventory location. Recording moves no stock.
create or replace function "better_supabase"."record_work_order_part"(work_order_id uuid, name text, quantity numeric default 1, unit text default null, asset_id uuid default null, variant_id uuid default null, location_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order "better_supabase"."work_orders"%rowtype;
  v_row "better_supabase"."work_order_parts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."work_orders" x where x."id" = record_work_order_part.work_order_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.manage'), false)) or (coalesce(v_order."technician_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.work'), false))) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if v_order."status" = 'cancelled' then
    raise exception 'a cancelled work order takes no parts' using errcode = '55000', hint = 'DISPATCH_STATUS_INVALID';
  end if;
  if record_work_order_part.asset_id is not null then
    raise exception 'install the assets block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_ASSETS_MISSING';
  end if;
  if record_work_order_part.variant_id is not null then
    raise exception 'install the catalog block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_CATALOG_MISSING';
  end if;
  if record_work_order_part.location_id is not null then
    raise exception 'install the inventory block to link work orders to it' using errcode = '22023', hint = 'DISPATCH_INVENTORY_MISSING';
  end if;
  begin
    insert into "better_supabase"."work_order_parts" ("tenant_id", "work_order_id", "name", "quantity", "unit", "asset_id", "variant_id", "location_id", "recorded_by")
    values (v_order."tenant_id", v_order."id", btrim(record_work_order_part.name), coalesce(record_work_order_part.quantity, 1),
      record_work_order_part.unit, record_work_order_part.asset_id, record_work_order_part.variant_id, record_work_order_part.location_id, auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or numeric_value_out_of_range then
    raise exception 'a part needs a name of 1 to 200 characters and a positive quantity' using errcode = '22023', hint = 'DISPATCH_PART_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'workOrderId', v_row."work_order_id", 'name', v_row."name", 'quantity', v_row."quantity"::text, 'unit', v_row."unit", 'assetId', v_row."asset_id", 'variantId', v_row."variant_id", 'locationId', v_row."location_id", 'recordedBy', v_row."recorded_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_work_order_part"(uuid, text, numeric, text, uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."record_work_order_part"(uuid, text, numeric, text, uuid, uuid, uuid) to authenticated, service_role;

-- A work order's parts, oldest first.
create or replace function "better_supabase"."list_work_order_parts"(work_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order "better_supabase"."work_orders"%rowtype;
begin
  select * into v_order from "better_supabase"."work_orders" x where x."id" = list_work_order_parts.work_order_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.read'), false)) or ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.manage'), false)) or (coalesce(v_order."technician_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.work'), false)))) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'workOrderId', y."work_order_id", 'name', y."name", 'quantity', y."quantity"::text, 'unit', y."unit", 'assetId', y."asset_id", 'variantId', y."variant_id", 'locationId', y."location_id", 'recordedBy', y."recorded_by", 'createdAt', y."created_at") order by y."created_at", y."id"), '[]'::jsonb)
    from "better_supabase"."work_order_parts" y where y."work_order_id" = v_order."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_work_order_parts"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_order_parts"(uuid) to authenticated, service_role;

-- Removes a part recorded by mistake: the dispatcher, or the technician who
-- recorded it.
create or replace function "better_supabase"."remove_work_order_part"(part_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_order_parts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_order_parts" y where y."id" = remove_work_order_part.part_id for update;
  if not found or not (
    (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false))
    or (coalesce(v_row."recorded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.work'), false))
  ) then
    return false;
  end if;
  delete from "better_supabase"."work_order_parts" y where y."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_work_order_part"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_work_order_part"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."work_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."dispatch_routes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."dispatch_routes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."dispatch_routes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."dispatch_routes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."dispatch_route_stops" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."dispatch_route_stops" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."dispatch_route_stops" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."dispatch_route_stops" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."work_order_parts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."work_order_parts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."work_order_parts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."work_order_parts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_123_dispatch.sql
-- better-supabase module: dispatch
-- @bsb-block-data dispatch
-- @bsb-hash sha256:06cac982f9d10a52b300a2913d8d96298562a0dc0c2043a5479ae1d6728664ef
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('dispatch', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
