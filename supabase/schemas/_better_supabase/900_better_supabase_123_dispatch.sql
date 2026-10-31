-- better-supabase module: dispatch
-- @bsb-block dispatch@1 managed
-- @bsb-hash sha256:876a43e3ff6f165d1681f3bf54588470df42621a71fc52e765a16a3d8a668b02
-- Field service work orders at asset locations: a schedule board of technicians' slots, a status lifecycle from scheduled to done, day routes with ordered stops, and the parts each job used, linked to assets or inventory when those blocks are installed.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."work_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."dispatch_routes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."dispatch_routes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dispatch_routes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."dispatch_routes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dispatch_routes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."dispatch_route_stops";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."dispatch_route_stops";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dispatch_route_stops";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."dispatch_route_stops";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dispatch_route_stops";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."work_order_parts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_order_parts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_order_parts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_order_parts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_order_parts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Dispatch: work orders at asset locations, scheduled into technicians'
-- slots on a board, worked through a status lifecycle, with day routes and
-- the parts each job used.

-- Work orders: a job at a place (an asset location or an address), for an
-- asset or a record, scheduled into a technician's slot and worked through
-- en route, on site and done.
create table if not exists "better_supabase"."work_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null check (length("title") >= 1 and length("title") <= 200),
  "description" text check ("description" is null or length("description") <= 10000),
  "priority" text not null default 'normal' check ("priority" in ('low', 'normal', 'high', 'urgent')),
  "status" text not null default 'unscheduled' check ("status" in ('unscheduled', 'scheduled', 'en_route', 'on_site', 'done', 'cancelled')),
  "technician_id" uuid references auth.users (id) on delete set null,
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "location_id" uuid,
  "asset_id" uuid,
  "booking_id" uuid,
  "subject_type" text check ("subject_type" is null or "subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check ("subject_id" is null or length("subject_id") >= 1 and length("subject_id") <= 200),
  "address" text check ("address" is null or length("address") >= 1 and length("address") <= 500),
  "en_route_at" timestamptz,
  "arrived_at" timestamptz,
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "completion_note" text check ("completion_note" is null or length("completion_note") <= 10000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  check (("starts_at" is null) = ("ends_at" is null)),
  check ("ends_at" is null or "ends_at" > "starts_at"),
  check ("status" not in ('scheduled', 'en_route', 'on_site') or ("technician_id" is not null and "starts_at" is not null))
);
create index if not exists "work_orders_tenant_idx" on "better_supabase"."work_orders" ("tenant_id", "created_at" desc);
create index if not exists "work_orders_slot_idx" on "better_supabase"."work_orders" ("technician_id", "starts_at") where "starts_at" is not null;
create index if not exists "work_orders_board_idx" on "better_supabase"."work_orders" ("tenant_id", "starts_at") where "starts_at" is not null;
create index if not exists "work_orders_backlog_idx" on "better_supabase"."work_orders" ("tenant_id", "created_at") where "status" = 'unscheduled';
create index if not exists "work_orders_location_idx" on "better_supabase"."work_orders" ("location_id");
create index if not exists "work_orders_asset_idx" on "better_supabase"."work_orders" ("asset_id");
create index if not exists "work_orders_booking_idx" on "better_supabase"."work_orders" ("booking_id");
create index if not exists "work_orders_subject_idx" on "better_supabase"."work_orders" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."work_orders" enable row level security;
revoke all on "better_supabase"."work_orders" from public, anon, authenticated;
grant select on "better_supabase"."work_orders" to authenticated;
grant all on "better_supabase"."work_orders" to service_role;
drop policy if exists "work_orders_read" on "better_supabase"."work_orders";
create policy work_orders_read on "better_supabase"."work_orders"
  for select to authenticated
  using ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
-- A technician's plan for one day: the work orders in the order they drive to
-- them.
create table if not exists "better_supabase"."dispatch_routes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "technician_id" uuid not null references auth.users (id) on delete cascade,
  "route_date" date not null,
  "planned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "technician_id", "route_date")
);
create index if not exists "dispatch_routes_technician_idx" on "better_supabase"."dispatch_routes" ("technician_id", "route_date");
alter table "better_supabase"."dispatch_routes" enable row level security;
revoke all on "better_supabase"."dispatch_routes" from public, anon, authenticated;
grant select on "better_supabase"."dispatch_routes" to authenticated;
grant all on "better_supabase"."dispatch_routes" to service_role;
drop policy if exists "dispatch_routes_read" on "better_supabase"."dispatch_routes";
create policy dispatch_routes_read on "better_supabase"."dispatch_routes"
  for select to authenticated
  using ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
create table if not exists "better_supabase"."dispatch_route_stops" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "route_id" uuid not null references "better_supabase"."dispatch_routes" ("id") on delete cascade,
  "work_order_id" uuid not null references "better_supabase"."work_orders" ("id") on delete cascade,
  "position" integer not null check ("position" >= 1),
  unique ("route_id", "position"),
  unique ("route_id", "work_order_id")
);
create index if not exists "dispatch_route_stops_job_idx" on "better_supabase"."dispatch_route_stops" ("work_order_id");
alter table "better_supabase"."dispatch_route_stops" enable row level security;
revoke all on "better_supabase"."dispatch_route_stops" from public, anon, authenticated;
grant select on "better_supabase"."dispatch_route_stops" to authenticated;
grant all on "better_supabase"."dispatch_route_stops" to service_role;
drop policy if exists "dispatch_route_stops_read" on "better_supabase"."dispatch_route_stops";
create policy dispatch_route_stops_read on "better_supabase"."dispatch_route_stops"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
-- The parts a job used: free text, or an asset, or a catalog variant taken
-- from an inventory location.
create table if not exists "better_supabase"."work_order_parts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "work_order_id" uuid not null references "better_supabase"."work_orders" ("id") on delete cascade,
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "quantity" numeric(14, 3) not null check ("quantity" > 0),
  "unit" text check ("unit" is null or length("unit") >= 1 and length("unit") <= 20),
  "asset_id" uuid,
  "variant_id" uuid,
  "location_id" uuid,
  "recorded_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "work_order_parts_job_idx" on "better_supabase"."work_order_parts" ("work_order_id", "created_at");
create index if not exists "work_order_parts_asset_idx" on "better_supabase"."work_order_parts" ("asset_id");
create index if not exists "work_order_parts_variant_idx" on "better_supabase"."work_order_parts" ("variant_id");
create index if not exists "work_order_parts_location_idx" on "better_supabase"."work_order_parts" ("location_id");
alter table "better_supabase"."work_order_parts" enable row level security;
revoke all on "better_supabase"."work_order_parts" from public, anon, authenticated;
grant select on "better_supabase"."work_order_parts" to authenticated;
grant all on "better_supabase"."work_order_parts" to service_role;
drop policy if exists "work_order_parts_read" on "better_supabase"."work_order_parts";
create policy work_order_parts_read on "better_supabase"."work_order_parts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')));
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_orders"'::regclass and conname = 'work_orders_location_fkey'
  ) then
    alter table "better_supabase"."work_orders" add constraint "work_orders_location_fkey"
      foreign key ("location_id") references "better_supabase"."asset_locations" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_orders" validate constraint "work_orders_location_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_orders"', '"better_supabase"."work_orders"', 'work_orders_location_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_orders"'::regclass and conname = 'work_orders_asset_fkey'
  ) then
    alter table "better_supabase"."work_orders" add constraint "work_orders_asset_fkey"
      foreign key ("asset_id") references "better_supabase"."assets" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_orders" validate constraint "work_orders_asset_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_orders"', '"better_supabase"."work_orders"', 'work_orders_asset_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_orders"'::regclass and conname = 'work_orders_booking_fkey'
  ) then
    alter table "better_supabase"."work_orders" add constraint "work_orders_booking_fkey"
      foreign key ("booking_id") references "better_supabase"."bookings" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_orders" validate constraint "work_orders_booking_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_orders"', '"better_supabase"."work_orders"', 'work_orders_booking_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_order_parts"'::regclass and conname = 'work_order_parts_asset_fkey'
  ) then
    alter table "better_supabase"."work_order_parts" add constraint "work_order_parts_asset_fkey"
      foreign key ("asset_id") references "better_supabase"."assets" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_order_parts" validate constraint "work_order_parts_asset_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_order_parts"', '"better_supabase"."work_order_parts"', 'work_order_parts_asset_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_order_parts"'::regclass and conname = 'work_order_parts_variant_fkey'
  ) then
    alter table "better_supabase"."work_order_parts" add constraint "work_order_parts_variant_fkey"
      foreign key ("variant_id") references "better_supabase"."product_variants" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_order_parts" validate constraint "work_order_parts_variant_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_order_parts"', '"better_supabase"."work_order_parts"', 'work_order_parts_variant_fkey';
    end;
  end if;
end;
$$;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."work_order_parts"'::regclass and conname = 'work_order_parts_location_fkey'
  ) then
    alter table "better_supabase"."work_order_parts" add constraint "work_order_parts_location_fkey"
      foreign key ("location_id") references "better_supabase"."inventory_locations" ("id") on delete set null not valid;
    begin
      alter table "better_supabase"."work_order_parts" validate constraint "work_order_parts_location_fkey";
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        '"better_supabase"."work_order_parts"', '"better_supabase"."work_order_parts"', 'work_order_parts_location_fkey';
    end;
  end if;
end;
$$;

drop function if exists "better_supabase"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz, jsonb);
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
  v_during tstzrange;
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
    and (case create_work_order.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (create_work_order.subject_id)::uuid)
      else null::text
    end) is distinct from create_work_order.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_SUBJECT_NOT_FOUND';
  end if;
  if create_work_order.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" l
    where l."id" = create_work_order.location_id and l."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_LOCATION_NOT_FOUND';
  end if;
  if create_work_order.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = create_work_order.asset_id and a."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
  end if;
  if create_work_order.booking_id is not null then
    select bk."during" into v_during from "better_supabase"."bookings" bk
      where bk."id" = create_work_order.booking_id and bk."tenant_id" = create_work_order.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_BOOKING_NOT_FOUND';
    end if;
  end if;
  if create_work_order.booking_id is not null and v_starts is null then
    v_starts := lower(v_during);
    v_ends := upper(v_during);
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
  perform "better_supabase".emit_event('work_order.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.created',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  if v_row."status" = 'scheduled' then
    perform "better_supabase".emit_event('work_order.scheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.scheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) to authenticated, service_role;

drop function if exists "better_supabase"."update_work_order"(uuid, text, text, text, uuid, uuid, text, jsonb);
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
  if update_work_order.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" l
    where l."id" = update_work_order.location_id and l."tenant_id" = v_row."tenant_id"
  ) then
    raise exception 'the location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_LOCATION_NOT_FOUND';
  end if;
  if update_work_order.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = update_work_order.asset_id and a."tenant_id" = v_row."tenant_id"
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
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
  perform "better_supabase".emit_event('work_order.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.updated',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'updated work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id")
  );
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
  perform "better_supabase".emit_event('work_order.scheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.scheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
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
  perform "better_supabase".emit_event('work_order.unscheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_technician), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.unscheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'unscheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_technician)
  );
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
  perform "better_supabase".emit_event('work_order.status_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'from', v_from, 'to', v_row."status", 'technicianId', v_row."technician_id"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.status_changed',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'work order ' || replace(v_row."status", '_', ' '),
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'from', v_from, 'to', v_row."status", 'technicianId', v_row."technician_id")
  );
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
  perform "better_supabase".emit_event('dispatch_route.planned', jsonb_build_object('organizationId', v_route."tenant_id"::text, 'id', v_route."id", 'technicianId', v_route."technician_id", 'routeDate', v_route."route_date", 'stops', v_count), 'dispatch-routes/' || v_route."id"::text, (v_route."tenant_id")::text, null, 'better-supabase/dispatch');
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
  if record_work_order_part.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = record_work_order_part.asset_id and a."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
  end if;
  if record_work_order_part.variant_id is not null and not exists (
    select 1 from "better_supabase"."product_variants" v
    where v."id" = record_work_order_part.variant_id and v."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the product variant does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_VARIANT_NOT_FOUND';
  end if;
  if record_work_order_part.location_id is not null and not exists (
    select 1 from "better_supabase"."inventory_locations" il
    where il."id" = record_work_order_part.location_id and il."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the inventory location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_INVENTORY_LOCATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."work_order_parts" ("tenant_id", "work_order_id", "name", "quantity", "unit", "asset_id", "variant_id", "location_id", "recorded_by")
    values (v_order."tenant_id", v_order."id", btrim(record_work_order_part.name), coalesce(record_work_order_part.quantity, 1),
      record_work_order_part.unit, record_work_order_part.asset_id, record_work_order_part.variant_id, record_work_order_part.location_id, auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or numeric_value_out_of_range then
    raise exception 'a part needs a name of 1 to 200 characters and a positive quantity' using errcode = '22023', hint = 'DISPATCH_PART_INVALID';
  end;
  perform "better_supabase".emit_event('work_order.part_used', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."work_order_id", 'partId', v_row."id", 'assetId', v_row."asset_id", 'variantId', v_row."variant_id", 'quantity', v_row."quantity"::text), 'work-orders/' || v_row."work_order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
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

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."dispatch_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.activities' then array['activity'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.leases' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.compliance_policies' then array['compliance_policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.cases' then array['case'] when 'better_supabase.inspections' then array['inspection'] when 'better_supabase.inspection_programs' then array['inspection_program'] when 'better_supabase.inspection_findings' then array['inspection_finding'] when 'better_supabase.forms' then array['form'] when 'better_supabase.production_orders' then array['production_order'] when 'better_supabase.work_centers' then array['work_center'] when 'better_supabase.bank_accounts' then array['bank_account'] when 'better_supabase.care_plans' then array['care_plan'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."work_orders" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."dispatch_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."dispatch_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

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
drop policy if exists bsb_tenant_scope on "better_supabase"."work_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_orders";
create policy bsb_tenant_scope_select on "better_supabase"."work_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."work_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_orders";
create policy bsb_tenant_scope_update on "better_supabase"."work_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."work_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."dispatch_routes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."dispatch_routes";
create policy bsb_tenant_scope_select on "better_supabase"."dispatch_routes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("technician_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dispatch_routes";
create policy bsb_tenant_scope_insert on "better_supabase"."dispatch_routes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."dispatch_routes";
create policy bsb_tenant_scope_update on "better_supabase"."dispatch_routes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dispatch_routes";
create policy bsb_tenant_scope_delete on "better_supabase"."dispatch_routes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."dispatch_route_stops";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."dispatch_route_stops";
create policy bsb_tenant_scope_select on "better_supabase"."dispatch_route_stops" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dispatch_route_stops";
create policy bsb_tenant_scope_insert on "better_supabase"."dispatch_route_stops" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."dispatch_route_stops";
create policy bsb_tenant_scope_update on "better_supabase"."dispatch_route_stops" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dispatch_route_stops";
create policy bsb_tenant_scope_delete on "better_supabase"."dispatch_route_stops" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."work_order_parts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_order_parts";
create policy bsb_tenant_scope_select on "better_supabase"."work_order_parts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dispatch.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_order_parts";
create policy bsb_tenant_scope_insert on "better_supabase"."work_order_parts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_order_parts";
create policy bsb_tenant_scope_update on "better_supabase"."work_order_parts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_order_parts";
create policy bsb_tenant_scope_delete on "better_supabase"."work_order_parts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.dispatch.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz, jsonb);
drop function if exists "api"."update_work_order"(uuid, text, text, text, uuid, uuid, text, jsonb);

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

create or replace function "api"."create_work_order"(tenant uuid, title text, description text default null, priority text default 'normal', location_id uuid default null, asset_id uuid default null, booking_id uuid default null, subject_type text default null, subject_id text default null, address text default null, technician uuid default null, starts_at timestamptz default null, ends_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_work_order"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) $$;
revoke execute on function "api"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "api"."create_work_order"(uuid, text, text, text, uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."update_work_order"(work_order_id uuid, title text default null, description text default null, priority text default null, location_id uuid default null, asset_id uuid default null, address text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_work_order"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."update_work_order"(uuid, text, text, text, uuid, uuid, text) from public, anon;
grant execute on function "api"."update_work_order"(uuid, text, text, text, uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."schedule_work_order"(work_order_id uuid, technician uuid, starts_at timestamptz, ends_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_work_order"($1, $2, $3, $4) $$;
revoke execute on function "api"."schedule_work_order"(uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "api"."schedule_work_order"(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."unschedule_work_order"(work_order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unschedule_work_order"($1) $$;
revoke execute on function "api"."unschedule_work_order"(uuid) from public, anon;
grant execute on function "api"."unschedule_work_order"(uuid) to authenticated, service_role;

create or replace function "api"."set_work_order_status"(work_order_id uuid, status text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_work_order_status"($1, $2, $3) $$;
revoke execute on function "api"."set_work_order_status"(uuid, text, text) from public, anon;
grant execute on function "api"."set_work_order_status"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_work_order"(work_order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_work_order"($1) $$;
revoke execute on function "api"."get_work_order"(uuid) from public, anon;
grant execute on function "api"."get_work_order"(uuid) to authenticated, service_role;

create or replace function "api"."list_work_orders"(tenant uuid, status text default null, technician uuid default null, subject_type text default null, subject_id text default null, from_at timestamptz default null, until_at timestamptz default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_orders"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."list_work_orders"(uuid, text, uuid, text, text, timestamptz, timestamptz, timestamptz, integer) from public, anon;
grant execute on function "api"."list_work_orders"(uuid, text, uuid, text, text, timestamptz, timestamptz, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."dispatch_board"(tenant uuid, from_date date, to_date date, technicians uuid[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dispatch_board"($1, $2, $3, $4) $$;
revoke execute on function "api"."dispatch_board"(uuid, date, date, uuid[]) from public, anon;
grant execute on function "api"."dispatch_board"(uuid, date, date, uuid[]) to authenticated, service_role;

create or replace function "api"."technician_day"(tenant uuid, day date, technician uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."technician_day"($1, $2, $3) $$;
revoke execute on function "api"."technician_day"(uuid, date, uuid) from public, anon;
grant execute on function "api"."technician_day"(uuid, date, uuid) to authenticated, service_role;

create or replace function "api"."plan_dispatch_route"(tenant uuid, technician uuid, route_date date, work_orders uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."plan_dispatch_route"($1, $2, $3, $4) $$;
revoke execute on function "api"."plan_dispatch_route"(uuid, uuid, date, uuid[]) from public, anon;
grant execute on function "api"."plan_dispatch_route"(uuid, uuid, date, uuid[]) to authenticated, service_role;

create or replace function "api"."record_work_order_part"(work_order_id uuid, name text, quantity numeric default 1, unit text default null, asset_id uuid default null, variant_id uuid default null, location_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_work_order_part"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_work_order_part"(uuid, text, numeric, text, uuid, uuid, uuid) from public, anon;
grant execute on function "api"."record_work_order_part"(uuid, text, numeric, text, uuid, uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_work_order_parts"(work_order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_work_order_parts"($1) $$;
revoke execute on function "api"."list_work_order_parts"(uuid) from public, anon;
grant execute on function "api"."list_work_order_parts"(uuid) to authenticated, service_role;

create or replace function "api"."remove_work_order_part"(part_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_work_order_part"($1) $$;
revoke execute on function "api"."remove_work_order_part"(uuid) from public, anon;
grant execute on function "api"."remove_work_order_part"(uuid) to authenticated, service_role;

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
