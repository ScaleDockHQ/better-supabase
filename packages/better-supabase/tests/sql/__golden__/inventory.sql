-- ==== alone: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:195e11ecc0ae8fb9194f32f23b27228042b67dae338740332ce5c50f51979491
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

create table if not exists "better_supabase"."inventory_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual')),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
alter table "better_supabase"."inventory_locations" enable row level security;
revoke all on "better_supabase"."inventory_locations" from public, anon, authenticated;
grant select on "better_supabase"."inventory_locations" to authenticated;
grant all on "better_supabase"."inventory_locations" to service_role;
drop policy if exists inventory_locations_read on "better_supabase"."inventory_locations";
create policy inventory_locations_read on "better_supabase"."inventory_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_levels" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "on_hand" numeric(20, 6) not null default 0,
  "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0),
  "held" numeric(20, 6) not null default 0 check ("held" >= 0),
  "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0),
  "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored,
  "reorder_point" numeric(20, 6) check ("reorder_point" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "location_id")
);
create index if not exists stock_levels_location_idx on "better_supabase"."stock_levels" ("location_id");
alter table "better_supabase"."stock_levels" enable row level security;
revoke all on "better_supabase"."stock_levels" from public, anon, authenticated;
grant select on "better_supabase"."stock_levels" to authenticated;
grant all on "better_supabase"."stock_levels" to service_role;
drop policy if exists stock_levels_read on "better_supabase"."stock_levels";
create policy stock_levels_read on "better_supabase"."stock_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_reservations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on "better_supabase"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "better_supabase"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "better_supabase"."stock_reservations" ("location_id");
alter table "better_supabase"."stock_reservations" enable row level security;
revoke all on "better_supabase"."stock_reservations" from public, anon, authenticated;
grant select on "better_supabase"."stock_reservations" to authenticated;
grant all on "better_supabase"."stock_reservations" to service_role;
drop policy if exists stock_reservations_read on "better_supabase"."stock_reservations";
create policy stock_reservations_read on "better_supabase"."stock_reservations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "from_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "to_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled')),
  "note" text,
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "received_at" timestamptz,
  check ("from_location_id" <> "to_location_id")
);
create index if not exists stock_transfers_from_idx on "better_supabase"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "better_supabase"."stock_transfers" ("to_location_id");
alter table "better_supabase"."stock_transfers" enable row level security;
revoke all on "better_supabase"."stock_transfers" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfers" to authenticated;
grant all on "better_supabase"."stock_transfers" to service_role;
drop policy if exists stock_transfers_read on "better_supabase"."stock_transfers";
create policy stock_transfers_read on "better_supabase"."stock_transfers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfer_lines" (
  "tenant_id" uuid not null,
  "transfer_id" uuid not null references "better_supabase"."stock_transfers" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  "detail" jsonb,
  primary key ("transfer_id", "variant_id")
);
create index if not exists stock_transfer_lines_variant_idx on "better_supabase"."stock_transfer_lines" ("variant_id");
alter table "better_supabase"."stock_transfer_lines" enable row level security;
revoke all on "better_supabase"."stock_transfer_lines" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfer_lines" to authenticated;
grant all on "better_supabase"."stock_transfer_lines" to service_role;
drop policy if exists stock_transfer_lines_read on "better_supabase"."stock_transfer_lines";
create policy stock_transfer_lines_read on "better_supabase"."stock_transfer_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "supplier_type" text,
  "supplier_id" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "expected_at" timestamptz,
  "note" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "placed_at" timestamptz,
  check (("supplier_type" is null) = ("supplier_id" is null))
);
create index if not exists purchase_orders_location_idx on "better_supabase"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "better_supabase"."purchase_orders" ("tenant_id", "status");
alter table "better_supabase"."purchase_orders" enable row level security;
revoke all on "better_supabase"."purchase_orders" from public, anon, authenticated;
grant select on "better_supabase"."purchase_orders" to authenticated;
grant all on "better_supabase"."purchase_orders" to service_role;
drop policy if exists purchase_orders_read on "better_supabase"."purchase_orders";
create policy purchase_orders_read on "better_supabase"."purchase_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "purchase_order_id" uuid not null references "better_supabase"."purchase_orders" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity_ordered" numeric(20, 6) not null check ("quantity_ordered" > 0),
  "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
  "unit_cost" bigint not null check ("unit_cost" >= 0),
  unique ("purchase_order_id", "variant_id")
);
create index if not exists purchase_order_lines_variant_idx on "better_supabase"."purchase_order_lines" ("variant_id");
alter table "better_supabase"."purchase_order_lines" enable row level security;
revoke all on "better_supabase"."purchase_order_lines" from public, anon, authenticated;
grant select on "better_supabase"."purchase_order_lines" to authenticated;
grant all on "better_supabase"."purchase_order_lines" to service_role;
drop policy if exists purchase_order_lines_read on "better_supabase"."purchase_order_lines";
create policy purchase_order_lines_read on "better_supabase"."purchase_order_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_items" (
  "variant_id" uuid primary key references "better_supabase"."product_variants" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$'),
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial')),
  "tracks_expiry" boolean not null default false,
  "costing" text not null default 'none' check ("costing" in ('none', 'average')),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "average_cost" numeric(24, 6) check ("average_cost" >= 0),
  "updated_at" timestamptz not null default now(),
  check ("tracking" <> 'serial' or "scale" = 0),
  check ("costing" = 'none' or "currency" is not null)
);
create index if not exists stock_items_tenant_idx on "better_supabase"."stock_items" ("tenant_id");
alter table "better_supabase"."stock_items" enable row level security;
revoke all on "better_supabase"."stock_items" from public, anon, authenticated;
grant select on "better_supabase"."stock_items" to authenticated;
grant all on "better_supabase"."stock_items" to service_role;
drop policy if exists stock_items_read on "better_supabase"."stock_items";
create policy stock_items_read on "better_supabase"."stock_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_bins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  "name" text check (length("name") between 1 and 200),
  "hold" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("location_id", "code")
);
create index if not exists stock_bins_tenant_idx on "better_supabase"."stock_bins" ("tenant_id");
alter table "better_supabase"."stock_bins" enable row level security;
revoke all on "better_supabase"."stock_bins" from public, anon, authenticated;
grant select on "better_supabase"."stock_bins" to authenticated;
grant all on "better_supabase"."stock_bins" to service_role;
drop policy if exists stock_bins_read on "better_supabase"."stock_bins";
create policy stock_bins_read on "better_supabase"."stock_bins"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_lots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "code" text not null check (length("code") between 1 and 100),
  "expires_on" date,
  "created_at" timestamptz not null default now(),
  unique ("variant_id", "code")
);
create index if not exists stock_lots_expiry_idx on "better_supabase"."stock_lots" ("tenant_id", "expires_on") where "expires_on" is not null;
alter table "better_supabase"."stock_lots" enable row level security;
revoke all on "better_supabase"."stock_lots" from public, anon, authenticated;
grant select on "better_supabase"."stock_lots" to authenticated;
grant all on "better_supabase"."stock_lots" to service_role;
drop policy if exists stock_lots_read on "better_supabase"."stock_lots";
create policy stock_lots_read on "better_supabase"."stock_lots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_serials" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "serial" text not null check (length("serial") between 1 and 100),
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete set null,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete set null,
  "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped')),
  "movement_id" uuid,
  "updated_at" timestamptz not null default now(),
  unique ("variant_id", "serial")
);
create index if not exists stock_serials_location_id_idx on "better_supabase"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "better_supabase"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "better_supabase"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "better_supabase"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "better_supabase"."stock_serials" ("tenant_id");
alter table "better_supabase"."stock_serials" enable row level security;
revoke all on "better_supabase"."stock_serials" from public, anon, authenticated;
grant select on "better_supabase"."stock_serials" to authenticated;
grant all on "better_supabase"."stock_serials" to service_role;
drop policy if exists stock_serials_read on "better_supabase"."stock_serials";
create policy stock_serials_read on "better_supabase"."stock_serials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_buckets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete restrict,
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict,
  "on_hand" numeric(20, 6) not null default 0,
  "updated_at" timestamptz not null default now(),
  check ("bin_id" is not null or "lot_id" is not null),
  unique nulls not distinct ("variant_id", "location_id", "bin_id", "lot_id")
);
create index if not exists stock_buckets_location_idx on "better_supabase"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "better_supabase"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "better_supabase"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "better_supabase"."stock_buckets" ("tenant_id");
alter table "better_supabase"."stock_buckets" enable row level security;
revoke all on "better_supabase"."stock_buckets" from public, anon, authenticated;
grant select on "better_supabase"."stock_buckets" to authenticated;
grant all on "better_supabase"."stock_buckets" to service_role;
drop policy if exists stock_buckets_read on "better_supabase"."stock_buckets";
create policy stock_buckets_read on "better_supabase"."stock_buckets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "line_id" text,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0),
  "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0),
  "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored,
  "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("allocated" + "fulfilled" <= "quantity")
);
create index if not exists stock_allocations_document_idx on "better_supabase"."stock_allocations" ("tenant_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "better_supabase"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "better_supabase"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "better_supabase"."stock_allocations" ("variant_id");
alter table "better_supabase"."stock_allocations" enable row level security;
revoke all on "better_supabase"."stock_allocations" from public, anon, authenticated;
grant select on "better_supabase"."stock_allocations" to authenticated;
grant all on "better_supabase"."stock_allocations" to service_role;
drop policy if exists stock_allocations_read on "better_supabase"."stock_allocations";
create policy stock_allocations_read on "better_supabase"."stock_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    null;
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "better_supabase"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."stock_items"%rowtype;
  v_old "better_supabase"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "better_supabase"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."tenant_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "better_supabase"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "better_supabase"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."stock_bins" ("tenant_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "better_supabase"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "better_supabase"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "better_supabase"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "better_supabase"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "better_supabase"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "better_supabase"."stock_lots" as x ("tenant_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "better_supabase"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "better_supabase"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "better_supabase"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "better_supabase"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "better_supabase"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "better_supabase"."stock_buckets" y
  left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
  left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "better_supabase"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "better_supabase"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "better_supabase"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "better_supabase"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "better_supabase"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "better_supabase"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "better_supabase"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "better_supabase"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."tenant_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."stock_valuation"(uuid) from public, anon;
grant execute on function "better_supabase"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "better_supabase"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "better_supabase"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    null;
  end loop;
  if v_total > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "better_supabase"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "better_supabase"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."tenant_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    left join "better_supabase"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."tenant_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location and y."tenant_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "better_supabase"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "better_supabase"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "better_supabase"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "better_supabase"."stock_allocations" x
    where x."tenant_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    null;
    if v_row.allocated > 0 then
      perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "better_supabase"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "better_supabase"."stock_allocations" x where x."tenant_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "better_supabase"."save_location"(uuid, uuid, text, text, text);
create or replace function "better_supabase"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "better_supabase"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "better_supabase"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_location"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "better_supabase"."count_stock"(uuid, uuid, integer, text);
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "better_supabase"."set_reorder_point"(uuid, uuid, integer);
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "better_supabase"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  null;
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "better_supabase"."commit_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "better_supabase"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "better_supabase"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "better_supabase"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "better_supabase"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "better_supabase"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "better_supabase"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "better_supabase"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "better_supabase"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "better_supabase"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "better_supabase"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "better_supabase"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."place_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "better_supabase"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  null;
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "better_supabase"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_purchase_order"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_select on "better_supabase"."inventory_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
create policy bsb_tenant_scope_select on "better_supabase"."stock_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
create policy bsb_tenant_scope_update on "better_supabase"."stock_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_select on "better_supabase"."stock_bins" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_bins" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_update on "better_supabase"."stock_bins" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_bins" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_select on "better_supabase"."stock_serials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_serials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_update on "better_supabase"."stock_serials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_serials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_select on "better_supabase"."stock_buckets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_buckets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_update on "better_supabase"."stock_buckets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_buckets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_allocations" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:a5a574fcf3b224578ec5e7854e96ef440b73382681355312a27c4e5a54ca66de
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

create table if not exists "better_supabase"."inventory_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual')),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
alter table "better_supabase"."inventory_locations" enable row level security;
revoke all on "better_supabase"."inventory_locations" from public, anon, authenticated;
grant select on "better_supabase"."inventory_locations" to authenticated;
grant all on "better_supabase"."inventory_locations" to service_role;
drop policy if exists inventory_locations_read on "better_supabase"."inventory_locations";
create policy inventory_locations_read on "better_supabase"."inventory_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_levels" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "on_hand" numeric(20, 6) not null default 0,
  "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0),
  "held" numeric(20, 6) not null default 0 check ("held" >= 0),
  "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0),
  "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored,
  "reorder_point" numeric(20, 6) check ("reorder_point" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "location_id")
);
create index if not exists stock_levels_location_idx on "better_supabase"."stock_levels" ("location_id");
alter table "better_supabase"."stock_levels" enable row level security;
revoke all on "better_supabase"."stock_levels" from public, anon, authenticated;
grant select on "better_supabase"."stock_levels" to authenticated;
grant all on "better_supabase"."stock_levels" to service_role;
drop policy if exists stock_levels_read on "better_supabase"."stock_levels";
create policy stock_levels_read on "better_supabase"."stock_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_reservations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on "better_supabase"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "better_supabase"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "better_supabase"."stock_reservations" ("location_id");
alter table "better_supabase"."stock_reservations" enable row level security;
revoke all on "better_supabase"."stock_reservations" from public, anon, authenticated;
grant select on "better_supabase"."stock_reservations" to authenticated;
grant all on "better_supabase"."stock_reservations" to service_role;
drop policy if exists stock_reservations_read on "better_supabase"."stock_reservations";
create policy stock_reservations_read on "better_supabase"."stock_reservations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "from_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "to_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled')),
  "note" text,
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "received_at" timestamptz,
  check ("from_location_id" <> "to_location_id")
);
create index if not exists stock_transfers_from_idx on "better_supabase"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "better_supabase"."stock_transfers" ("to_location_id");
alter table "better_supabase"."stock_transfers" enable row level security;
revoke all on "better_supabase"."stock_transfers" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfers" to authenticated;
grant all on "better_supabase"."stock_transfers" to service_role;
drop policy if exists stock_transfers_read on "better_supabase"."stock_transfers";
create policy stock_transfers_read on "better_supabase"."stock_transfers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfer_lines" (
  "tenant_id" uuid not null,
  "transfer_id" uuid not null references "better_supabase"."stock_transfers" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  "detail" jsonb,
  primary key ("transfer_id", "variant_id")
);
create index if not exists stock_transfer_lines_variant_idx on "better_supabase"."stock_transfer_lines" ("variant_id");
alter table "better_supabase"."stock_transfer_lines" enable row level security;
revoke all on "better_supabase"."stock_transfer_lines" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfer_lines" to authenticated;
grant all on "better_supabase"."stock_transfer_lines" to service_role;
drop policy if exists stock_transfer_lines_read on "better_supabase"."stock_transfer_lines";
create policy stock_transfer_lines_read on "better_supabase"."stock_transfer_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "supplier_type" text,
  "supplier_id" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "expected_at" timestamptz,
  "note" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "placed_at" timestamptz,
  check (("supplier_type" is null) = ("supplier_id" is null))
);
create index if not exists purchase_orders_location_idx on "better_supabase"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "better_supabase"."purchase_orders" ("tenant_id", "status");
alter table "better_supabase"."purchase_orders" enable row level security;
revoke all on "better_supabase"."purchase_orders" from public, anon, authenticated;
grant select on "better_supabase"."purchase_orders" to authenticated;
grant all on "better_supabase"."purchase_orders" to service_role;
drop policy if exists purchase_orders_read on "better_supabase"."purchase_orders";
create policy purchase_orders_read on "better_supabase"."purchase_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "purchase_order_id" uuid not null references "better_supabase"."purchase_orders" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity_ordered" numeric(20, 6) not null check ("quantity_ordered" > 0),
  "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
  "unit_cost" bigint not null check ("unit_cost" >= 0),
  unique ("purchase_order_id", "variant_id")
);
create index if not exists purchase_order_lines_variant_idx on "better_supabase"."purchase_order_lines" ("variant_id");
alter table "better_supabase"."purchase_order_lines" enable row level security;
revoke all on "better_supabase"."purchase_order_lines" from public, anon, authenticated;
grant select on "better_supabase"."purchase_order_lines" to authenticated;
grant all on "better_supabase"."purchase_order_lines" to service_role;
drop policy if exists purchase_order_lines_read on "better_supabase"."purchase_order_lines";
create policy purchase_order_lines_read on "better_supabase"."purchase_order_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_items" (
  "variant_id" uuid primary key references "better_supabase"."product_variants" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$'),
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial')),
  "tracks_expiry" boolean not null default false,
  "costing" text not null default 'none' check ("costing" in ('none', 'average')),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "average_cost" numeric(24, 6) check ("average_cost" >= 0),
  "updated_at" timestamptz not null default now(),
  check ("tracking" <> 'serial' or "scale" = 0),
  check ("costing" = 'none' or "currency" is not null)
);
create index if not exists stock_items_tenant_idx on "better_supabase"."stock_items" ("tenant_id");
alter table "better_supabase"."stock_items" enable row level security;
revoke all on "better_supabase"."stock_items" from public, anon, authenticated;
grant select on "better_supabase"."stock_items" to authenticated;
grant all on "better_supabase"."stock_items" to service_role;
drop policy if exists stock_items_read on "better_supabase"."stock_items";
create policy stock_items_read on "better_supabase"."stock_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_bins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  "name" text check (length("name") between 1 and 200),
  "hold" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("location_id", "code")
);
create index if not exists stock_bins_tenant_idx on "better_supabase"."stock_bins" ("tenant_id");
alter table "better_supabase"."stock_bins" enable row level security;
revoke all on "better_supabase"."stock_bins" from public, anon, authenticated;
grant select on "better_supabase"."stock_bins" to authenticated;
grant all on "better_supabase"."stock_bins" to service_role;
drop policy if exists stock_bins_read on "better_supabase"."stock_bins";
create policy stock_bins_read on "better_supabase"."stock_bins"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_lots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "code" text not null check (length("code") between 1 and 100),
  "expires_on" date,
  "created_at" timestamptz not null default now(),
  unique ("variant_id", "code")
);
create index if not exists stock_lots_expiry_idx on "better_supabase"."stock_lots" ("tenant_id", "expires_on") where "expires_on" is not null;
alter table "better_supabase"."stock_lots" enable row level security;
revoke all on "better_supabase"."stock_lots" from public, anon, authenticated;
grant select on "better_supabase"."stock_lots" to authenticated;
grant all on "better_supabase"."stock_lots" to service_role;
drop policy if exists stock_lots_read on "better_supabase"."stock_lots";
create policy stock_lots_read on "better_supabase"."stock_lots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_serials" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "serial" text not null check (length("serial") between 1 and 100),
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete set null,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete set null,
  "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped')),
  "movement_id" uuid,
  "updated_at" timestamptz not null default now(),
  unique ("variant_id", "serial")
);
create index if not exists stock_serials_location_id_idx on "better_supabase"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "better_supabase"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "better_supabase"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "better_supabase"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "better_supabase"."stock_serials" ("tenant_id");
alter table "better_supabase"."stock_serials" enable row level security;
revoke all on "better_supabase"."stock_serials" from public, anon, authenticated;
grant select on "better_supabase"."stock_serials" to authenticated;
grant all on "better_supabase"."stock_serials" to service_role;
drop policy if exists stock_serials_read on "better_supabase"."stock_serials";
create policy stock_serials_read on "better_supabase"."stock_serials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_buckets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete restrict,
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict,
  "on_hand" numeric(20, 6) not null default 0,
  "updated_at" timestamptz not null default now(),
  check ("bin_id" is not null or "lot_id" is not null),
  unique nulls not distinct ("variant_id", "location_id", "bin_id", "lot_id")
);
create index if not exists stock_buckets_location_idx on "better_supabase"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "better_supabase"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "better_supabase"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "better_supabase"."stock_buckets" ("tenant_id");
alter table "better_supabase"."stock_buckets" enable row level security;
revoke all on "better_supabase"."stock_buckets" from public, anon, authenticated;
grant select on "better_supabase"."stock_buckets" to authenticated;
grant all on "better_supabase"."stock_buckets" to service_role;
drop policy if exists stock_buckets_read on "better_supabase"."stock_buckets";
create policy stock_buckets_read on "better_supabase"."stock_buckets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "line_id" text,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0),
  "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0),
  "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored,
  "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("allocated" + "fulfilled" <= "quantity")
);
create index if not exists stock_allocations_document_idx on "better_supabase"."stock_allocations" ("tenant_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "better_supabase"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "better_supabase"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "better_supabase"."stock_allocations" ("variant_id");
alter table "better_supabase"."stock_allocations" enable row level security;
revoke all on "better_supabase"."stock_allocations" from public, anon, authenticated;
grant select on "better_supabase"."stock_allocations" to authenticated;
grant all on "better_supabase"."stock_allocations" to service_role;
drop policy if exists stock_allocations_read on "better_supabase"."stock_allocations";
create policy stock_allocations_read on "better_supabase"."stock_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_value <> 0 then
    perform "better_supabase"."accounting_post_source"('stock_movement', v_id::text);
  end if;
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', move_stock.tenant, 'subjectType', 'product_variant', 'subjectId', move_stock.variant::text, 'variantId', move_stock.variant, 'locationId', move_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || move_stock.variant::text || '/' || move_stock.location::text, (move_stock.tenant)::text, null, 'better-supabase/inventory');
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "better_supabase"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."stock_items"%rowtype;
  v_old "better_supabase"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "better_supabase"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."tenant_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "better_supabase"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "better_supabase"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."stock_bins" ("tenant_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "better_supabase"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "better_supabase"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "better_supabase"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "better_supabase"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "better_supabase"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "better_supabase"."stock_lots" as x ("tenant_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "better_supabase"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "better_supabase"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "better_supabase"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "better_supabase"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "better_supabase"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "better_supabase"."stock_buckets" y
  left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
  left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "better_supabase"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "better_supabase"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "better_supabase"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "better_supabase"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "better_supabase"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "better_supabase"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "better_supabase"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "better_supabase"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."tenant_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."stock_valuation"(uuid) from public, anon;
grant execute on function "better_supabase"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "better_supabase"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "better_supabase"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    perform "better_supabase".emit_event('allocation.filled', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text, 'allocated', v_take::text), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  end loop;
  if v_total > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "better_supabase"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "better_supabase"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."tenant_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    left join "better_supabase"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."tenant_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location and y."tenant_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  perform "better_supabase".emit_event('allocation.created', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text, 'allocated', v_take::text), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "better_supabase"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "better_supabase"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "better_supabase"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "better_supabase"."stock_allocations" x
    where x."tenant_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    perform "better_supabase".emit_event('allocation.released', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location,
        'documentType', v_row.document_type, 'documentId', v_row.document_id, 'quantity', v_row.quantity::text), 'stock-allocations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
    if v_row.allocated > 0 then
      perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "better_supabase"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "better_supabase"."stock_allocations" x where x."tenant_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "better_supabase"."save_location"(uuid, uuid, text, text, text);
create or replace function "better_supabase"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "better_supabase"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "better_supabase"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_location"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  perform "better_supabase".emit_event('stock.adjusted', jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', adjust_stock.variant, 'locationId', adjust_stock.location, 'quantity', adjust_stock.quantity::text, 'reason', adjust_stock.reason, 'available', v_available::text), 'stock-movements/' || v_movement::text, (v_tenant)::text, null, 'better-supabase/inventory');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "better_supabase"."count_stock"(uuid, uuid, integer, text);
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    perform "better_supabase".emit_event('stock.adjusted', jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', count_stock.variant, 'locationId', count_stock.location, 'quantity', v_delta::text, 'reason', 'count', 'available', v_available::text), 'stock-movements/' || v_movement::text, (v_tenant)::text, null, 'better-supabase/inventory');
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "better_supabase"."set_reorder_point"(uuid, uuid, integer);
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', v_tenant, 'subjectType', 'product_variant', 'subjectId', reserve_stock.variant::text, 'variantId', reserve_stock.variant, 'locationId', reserve_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || reserve_stock.variant::text || '/' || reserve_stock.location::text, (v_tenant)::text, null, 'better-supabase/inventory');
  end if;
  perform "better_supabase".emit_event('reservation.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'variantId', reserve_stock.variant, 'locationId', reserve_stock.location, 'quantity', reserve_stock.quantity::text), 'stock-reservations/' || v_id::text, (v_tenant)::text, null, 'better-supabase/inventory');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "better_supabase"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  perform "better_supabase".emit_event('reservation.committed', jsonb_build_object('organizationId', v_row.tenant, 'id', commit_reservation.reservation, 'variantId', v_row.variant, 'locationId', v_row.location, 'quantity', v_row.quantity::text), 'stock-reservations/' || commit_reservation.reservation::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "better_supabase"."commit_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "better_supabase"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "better_supabase"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  perform "better_supabase".emit_event('reservation.released', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location, 'quantity', v_row.quantity::text, 'reason', 'released'), 'stock-reservations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "better_supabase"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "better_supabase"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    perform "better_supabase".emit_event('reservation.released', jsonb_build_object('organizationId', v_row.tenant, 'id', v_row.id, 'variantId', v_row.variant, 'locationId', v_row.location, 'quantity', v_row.quantity::text, 'reason', 'expired'), 'stock-reservations/' || v_row.id::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "better_supabase"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "better_supabase"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "better_supabase"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  perform "better_supabase".emit_event('transfer.shipped', jsonb_build_object('organizationId', v_row.tenant, 'id', ship_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'in_transit'), 'stock-transfers/' || ship_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "better_supabase"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  perform "better_supabase".emit_event('transfer.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'received'), 'stock-transfers/' || receive_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "better_supabase"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  perform "better_supabase".emit_event('transfer.cancelled', jsonb_build_object('organizationId', v_row.tenant, 'id', cancel_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'cancelled'), 'stock-transfers/' || cancel_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "better_supabase"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "better_supabase"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.placed', jsonb_build_object('organizationId', v_row.tenant, 'id', place_purchase_order.purchase_order, 'locationId', v_row.location, 'status', 'ordered', 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || place_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."place_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "better_supabase"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'status', v_status, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || receive_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "better_supabase"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.cancelled', jsonb_build_object('organizationId', v_row.tenant, 'id', cancel_purchase_order.purchase_order, 'locationId', v_row.location, 'status', 'cancelled', 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || cancel_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_purchase_order"(uuid) to authenticated, service_role;

-- The entry of a stock movement's value for accounting: inventory against the
-- supplier, cost of goods sold or expense.
create or replace function "better_supabase"."accounting_stock_movement_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', a."unit",
    'reference', y."reference_id",
    'memo', 'Stock ' || (y."metadata" ->> 'reason'),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'inventory', 'debit', e."amount"::text),
      jsonb_build_object('role', case y."metadata" ->> 'reason' when 'receipt' then 'payable' when 'sale' then 'cogs' when 'return' then 'cogs' else 'expense' end,
        'credit', e."amount"::text))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."ledger_entries" e on e."transaction_id" = y."id"
  join "better_supabase"."ledger_accounts" a on a."id" = e."account_id" and a."kind" = 'stock_value'
  where y."id"::text = source_id and e."amount" <> 0
  limit 1
$$;
revoke execute on function "better_supabase"."accounting_stock_movement_lines"(text) from public, anon, authenticated;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_select on "better_supabase"."inventory_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
create policy bsb_tenant_scope_select on "better_supabase"."stock_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
create policy bsb_tenant_scope_update on "better_supabase"."stock_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_select on "better_supabase"."stock_bins" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_bins" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_update on "better_supabase"."stock_bins" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_bins" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_select on "better_supabase"."stock_serials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_serials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_update on "better_supabase"."stock_serials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_serials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_select on "better_supabase"."stock_buckets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_buckets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_update on "better_supabase"."stock_buckets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_buckets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_allocations" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:e4d5114e294af91b0f7beefca573f562c01e40daa537f2950894b5d93075710d
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "app_private"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "app_private"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "app_private"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_allocations";
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
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

create table if not exists "app_private"."inventory_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual')),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
alter table "app_private"."inventory_locations" enable row level security;
revoke all on "app_private"."inventory_locations" from public, anon, authenticated;
grant select on "app_private"."inventory_locations" to authenticated;
grant all on "app_private"."inventory_locations" to service_role;
drop policy if exists inventory_locations_read on "app_private"."inventory_locations";
create policy inventory_locations_read on "app_private"."inventory_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_levels" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "on_hand" numeric(20, 6) not null default 0,
  "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0),
  "held" numeric(20, 6) not null default 0 check ("held" >= 0),
  "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0),
  "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored,
  "reorder_point" numeric(20, 6) check ("reorder_point" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "location_id")
);
create index if not exists stock_levels_location_idx on "app_private"."stock_levels" ("location_id");
alter table "app_private"."stock_levels" enable row level security;
revoke all on "app_private"."stock_levels" from public, anon, authenticated;
grant select on "app_private"."stock_levels" to authenticated;
grant all on "app_private"."stock_levels" to service_role;
drop policy if exists stock_levels_read on "app_private"."stock_levels";
create policy stock_levels_read on "app_private"."stock_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_reservations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on "app_private"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "app_private"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "app_private"."stock_reservations" ("location_id");
alter table "app_private"."stock_reservations" enable row level security;
revoke all on "app_private"."stock_reservations" from public, anon, authenticated;
grant select on "app_private"."stock_reservations" to authenticated;
grant all on "app_private"."stock_reservations" to service_role;
drop policy if exists stock_reservations_read on "app_private"."stock_reservations";
create policy stock_reservations_read on "app_private"."stock_reservations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_transfers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "from_location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "to_location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled')),
  "note" text,
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "received_at" timestamptz,
  check ("from_location_id" <> "to_location_id")
);
create index if not exists stock_transfers_from_idx on "app_private"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "app_private"."stock_transfers" ("to_location_id");
alter table "app_private"."stock_transfers" enable row level security;
revoke all on "app_private"."stock_transfers" from public, anon, authenticated;
grant select on "app_private"."stock_transfers" to authenticated;
grant all on "app_private"."stock_transfers" to service_role;
drop policy if exists stock_transfers_read on "app_private"."stock_transfers";
create policy stock_transfers_read on "app_private"."stock_transfers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_transfer_lines" (
  "tenant_id" uuid not null,
  "transfer_id" uuid not null references "app_private"."stock_transfers" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  "detail" jsonb,
  primary key ("transfer_id", "variant_id")
);
create index if not exists stock_transfer_lines_variant_idx on "app_private"."stock_transfer_lines" ("variant_id");
alter table "app_private"."stock_transfer_lines" enable row level security;
revoke all on "app_private"."stock_transfer_lines" from public, anon, authenticated;
grant select on "app_private"."stock_transfer_lines" to authenticated;
grant all on "app_private"."stock_transfer_lines" to service_role;
drop policy if exists stock_transfer_lines_read on "app_private"."stock_transfer_lines";
create policy stock_transfer_lines_read on "app_private"."stock_transfer_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."purchase_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "supplier_type" text,
  "supplier_id" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "expected_at" timestamptz,
  "note" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "placed_at" timestamptz,
  check (("supplier_type" is null) = ("supplier_id" is null))
);
create index if not exists purchase_orders_location_idx on "app_private"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "app_private"."purchase_orders" ("tenant_id", "status");
alter table "app_private"."purchase_orders" enable row level security;
revoke all on "app_private"."purchase_orders" from public, anon, authenticated;
grant select on "app_private"."purchase_orders" to authenticated;
grant all on "app_private"."purchase_orders" to service_role;
drop policy if exists purchase_orders_read on "app_private"."purchase_orders";
create policy purchase_orders_read on "app_private"."purchase_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."purchase_order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "purchase_order_id" uuid not null references "app_private"."purchase_orders" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity_ordered" numeric(20, 6) not null check ("quantity_ordered" > 0),
  "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
  "unit_cost" bigint not null check ("unit_cost" >= 0),
  unique ("purchase_order_id", "variant_id")
);
create index if not exists purchase_order_lines_variant_idx on "app_private"."purchase_order_lines" ("variant_id");
alter table "app_private"."purchase_order_lines" enable row level security;
revoke all on "app_private"."purchase_order_lines" from public, anon, authenticated;
grant select on "app_private"."purchase_order_lines" to authenticated;
grant all on "app_private"."purchase_order_lines" to service_role;
drop policy if exists purchase_order_lines_read on "app_private"."purchase_order_lines";
create policy purchase_order_lines_read on "app_private"."purchase_order_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_items" (
  "variant_id" uuid primary key references "better_supabase"."product_variants" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$'),
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial')),
  "tracks_expiry" boolean not null default false,
  "costing" text not null default 'none' check ("costing" in ('none', 'average')),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "average_cost" numeric(24, 6) check ("average_cost" >= 0),
  "updated_at" timestamptz not null default now(),
  check ("tracking" <> 'serial' or "scale" = 0),
  check ("costing" = 'none' or "currency" is not null)
);
create index if not exists stock_items_tenant_idx on "app_private"."stock_items" ("tenant_id");
alter table "app_private"."stock_items" enable row level security;
revoke all on "app_private"."stock_items" from public, anon, authenticated;
grant select on "app_private"."stock_items" to authenticated;
grant all on "app_private"."stock_items" to service_role;
drop policy if exists stock_items_read on "app_private"."stock_items";
create policy stock_items_read on "app_private"."stock_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_bins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  "name" text check (length("name") between 1 and 200),
  "hold" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("location_id", "code")
);
create index if not exists stock_bins_tenant_idx on "app_private"."stock_bins" ("tenant_id");
alter table "app_private"."stock_bins" enable row level security;
revoke all on "app_private"."stock_bins" from public, anon, authenticated;
grant select on "app_private"."stock_bins" to authenticated;
grant all on "app_private"."stock_bins" to service_role;
drop policy if exists stock_bins_read on "app_private"."stock_bins";
create policy stock_bins_read on "app_private"."stock_bins"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_lots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "code" text not null check (length("code") between 1 and 100),
  "expires_on" date,
  "created_at" timestamptz not null default now(),
  unique ("variant_id", "code")
);
create index if not exists stock_lots_expiry_idx on "app_private"."stock_lots" ("tenant_id", "expires_on") where "expires_on" is not null;
alter table "app_private"."stock_lots" enable row level security;
revoke all on "app_private"."stock_lots" from public, anon, authenticated;
grant select on "app_private"."stock_lots" to authenticated;
grant all on "app_private"."stock_lots" to service_role;
drop policy if exists stock_lots_read on "app_private"."stock_lots";
create policy stock_lots_read on "app_private"."stock_lots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_serials" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "serial" text not null check (length("serial") between 1 and 100),
  "lot_id" uuid references "app_private"."stock_lots" ("id") on delete set null,
  "location_id" uuid references "app_private"."inventory_locations" ("id") on delete set null,
  "bin_id" uuid references "app_private"."stock_bins" ("id") on delete set null,
  "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped')),
  "movement_id" uuid,
  "updated_at" timestamptz not null default now(),
  unique ("variant_id", "serial")
);
create index if not exists stock_serials_location_id_idx on "app_private"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "app_private"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "app_private"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "app_private"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "app_private"."stock_serials" ("tenant_id");
alter table "app_private"."stock_serials" enable row level security;
revoke all on "app_private"."stock_serials" from public, anon, authenticated;
grant select on "app_private"."stock_serials" to authenticated;
grant all on "app_private"."stock_serials" to service_role;
drop policy if exists stock_serials_read on "app_private"."stock_serials";
create policy stock_serials_read on "app_private"."stock_serials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_buckets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid references "app_private"."stock_bins" ("id") on delete restrict,
  "lot_id" uuid references "app_private"."stock_lots" ("id") on delete restrict,
  "on_hand" numeric(20, 6) not null default 0,
  "updated_at" timestamptz not null default now(),
  check ("bin_id" is not null or "lot_id" is not null),
  unique nulls not distinct ("variant_id", "location_id", "bin_id", "lot_id")
);
create index if not exists stock_buckets_location_idx on "app_private"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "app_private"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "app_private"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "app_private"."stock_buckets" ("tenant_id");
alter table "app_private"."stock_buckets" enable row level security;
revoke all on "app_private"."stock_buckets" from public, anon, authenticated;
grant select on "app_private"."stock_buckets" to authenticated;
grant all on "app_private"."stock_buckets" to service_role;
drop policy if exists stock_buckets_read on "app_private"."stock_buckets";
create policy stock_buckets_read on "app_private"."stock_buckets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "app_private"."stock_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "app_private"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "line_id" text,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0),
  "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0),
  "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored,
  "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("allocated" + "fulfilled" <= "quantity")
);
create index if not exists stock_allocations_document_idx on "app_private"."stock_allocations" ("tenant_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "app_private"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "app_private"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "app_private"."stock_allocations" ("variant_id");
alter table "app_private"."stock_allocations" enable row level security;
revoke all on "app_private"."stock_allocations" from public, anon, authenticated;
grant select on "app_private"."stock_allocations" to authenticated;
grant all on "app_private"."stock_allocations" to service_role;
drop policy if exists stock_allocations_read on "app_private"."stock_allocations";
create policy stock_allocations_read on "app_private"."stock_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "app_private"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "app_private"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "app_private"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "app_private"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "app_private"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "app_private"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "app_private"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "app_private"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "app_private"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "app_private"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "app_private"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "app_private"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "app_private"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "app_private"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "app_private"."stock_buckets" y
      left join "app_private"."stock_bins" bn on bn."id" = y."bin_id"
      left join "app_private"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "app_private"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "app_private"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "app_private"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "app_private"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update "app_private"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "app_private"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "app_private"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    null;
  end if;
  if move_stock.quantity > 0 then
    perform "app_private"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "app_private"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "app_private"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "app_private"."stock_items"%rowtype;
  v_old "app_private"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "app_private"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."tenant_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "app_private"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "app_private"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "app_private"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "app_private"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."stock_bins" ("tenant_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "app_private"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "app_private"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "app_private"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "app_private"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "app_private"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "app_private"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "app_private"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "app_private"."stock_lots" as x ("tenant_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "app_private"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "app_private"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "app_private"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "app_private"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "app_private"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "app_private"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."tenant_id" into v_tenant from "app_private"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "app_private"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "app_private"."stock_buckets" y
  left join "app_private"."stock_bins" bn on bn."id" = y."bin_id"
  left join "app_private"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "app_private"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "app_private"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "app_private"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "app_private"."stock_buckets" y join "app_private"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "app_private"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "app_private"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "app_private"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "app_private"."stock_buckets" y join "app_private"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "app_private"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_lots"(uuid, date) from public, anon;
grant execute on function "app_private"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "app_private"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "app_private"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "app_private"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."tenant_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "app_private"."stock_valuation"(uuid) from public, anon;
grant execute on function "app_private"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "app_private"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "app_private"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "app_private"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "app_private"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    null;
  end loop;
  if v_total > 0 then
    update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "app_private"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "app_private"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."tenant_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "app_private"."inventory_locations" y
    left join "app_private"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."tenant_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "app_private"."inventory_locations" y where y."id" = v_location and y."tenant_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "app_private"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "app_private"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "app_private"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "app_private"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "app_private"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "app_private"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "app_private"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "app_private"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "app_private"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "app_private"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "app_private"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "app_private"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "app_private"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "app_private"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "app_private"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "app_private"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "app_private"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "app_private"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "app_private"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "app_private"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "app_private"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "app_private"."stock_allocations" x
    where x."tenant_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "app_private"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    null;
    if v_row.allocated > 0 then
      perform "app_private"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "app_private"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "app_private"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "app_private"."stock_allocations" x where x."tenant_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "app_private"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "app_private"."save_location"(uuid, uuid, text, text, text);
create or replace function "app_private"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "app_private"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "app_private"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "app_private"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "app_private"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "app_private"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "app_private"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "app_private"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "app_private"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "app_private"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "app_private"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "app_private"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_location"(uuid) from public, anon;
grant execute on function "app_private"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "app_private"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "app_private"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "app_private"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "app_private"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "app_private"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "app_private"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "app_private"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "app_private"."count_stock"(uuid, uuid, integer, text);
create or replace function "app_private"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "app_private"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "app_private"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "app_private"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "app_private"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "app_private"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "app_private"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "app_private"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "app_private"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "app_private"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "app_private"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "app_private"."set_reorder_point"(uuid, uuid, integer);
create or replace function "app_private"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "app_private"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "app_private"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "app_private"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "app_private"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "app_private"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "app_private"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "app_private"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "app_private"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "app_private"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "app_private"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "app_private"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "app_private"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "app_private"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "app_private"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "app_private"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "app_private"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "app_private"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "app_private"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "app_private"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  null;
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "app_private"."commit_reservation"(uuid) from public, anon;
grant execute on function "app_private"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "app_private"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "app_private"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "app_private"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."release_reservation"(uuid) from public, anon;
grant execute on function "app_private"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "app_private"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "app_private"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "app_private"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "app_private"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "app_private"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "app_private"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "app_private"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "app_private"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "app_private"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "app_private"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "app_private"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "app_private"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "app_private"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "app_private"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "app_private"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "app_private"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "app_private"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."ship_transfer"(uuid) from public, anon;
grant execute on function "app_private"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "app_private"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "app_private"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "app_private"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "app_private"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "app_private"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "app_private"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."receive_transfer"(uuid) from public, anon;
grant execute on function "app_private"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "app_private"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "app_private"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "app_private"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "app_private"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "app_private"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "app_private"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."cancel_transfer"(uuid) from public, anon;
grant execute on function "app_private"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "app_private"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "app_private"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "app_private"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "app_private"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "app_private"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "app_private"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "app_private"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "app_private"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "app_private"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "app_private"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "app_private"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "app_private"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "app_private"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "app_private"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."place_purchase_order"(uuid) from public, anon;
grant execute on function "app_private"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "app_private"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "app_private"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "app_private"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "app_private"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "app_private"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "app_private"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "app_private"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "app_private"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  null;
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "app_private"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "app_private"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "app_private"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "app_private"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "app_private"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "app_private"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "app_private"."cancel_purchase_order"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "app_private"."inventory_locations";
create policy bsb_tenant_scope_select on "app_private"."inventory_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."inventory_locations";
create policy bsb_tenant_scope_insert on "app_private"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."inventory_locations";
create policy bsb_tenant_scope_update on "app_private"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."inventory_locations";
create policy bsb_tenant_scope_delete on "app_private"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_levels";
create policy bsb_tenant_scope_select on "app_private"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_levels";
create policy bsb_tenant_scope_insert on "app_private"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_levels";
create policy bsb_tenant_scope_update on "app_private"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_levels";
create policy bsb_tenant_scope_delete on "app_private"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_reservations";
create policy bsb_tenant_scope_select on "app_private"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_reservations";
create policy bsb_tenant_scope_insert on "app_private"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_reservations";
create policy bsb_tenant_scope_update on "app_private"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_reservations";
create policy bsb_tenant_scope_delete on "app_private"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_transfers";
create policy bsb_tenant_scope_select on "app_private"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_transfers";
create policy bsb_tenant_scope_insert on "app_private"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_transfers";
create policy bsb_tenant_scope_update on "app_private"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_transfers";
create policy bsb_tenant_scope_delete on "app_private"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "app_private"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "app_private"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "app_private"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "app_private"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "app_private"."purchase_orders";
create policy bsb_tenant_scope_select on "app_private"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."purchase_orders";
create policy bsb_tenant_scope_insert on "app_private"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."purchase_orders";
create policy bsb_tenant_scope_update on "app_private"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."purchase_orders";
create policy bsb_tenant_scope_delete on "app_private"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."purchase_order_lines";
create policy bsb_tenant_scope_select on "app_private"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "app_private"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."purchase_order_lines";
create policy bsb_tenant_scope_update on "app_private"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "app_private"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_items";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_items";
create policy bsb_tenant_scope_select on "app_private"."stock_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_items";
create policy bsb_tenant_scope_insert on "app_private"."stock_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_items";
create policy bsb_tenant_scope_update on "app_private"."stock_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_items";
create policy bsb_tenant_scope_delete on "app_private"."stock_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_bins";
create policy bsb_tenant_scope_select on "app_private"."stock_bins" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_bins";
create policy bsb_tenant_scope_insert on "app_private"."stock_bins" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_bins";
create policy bsb_tenant_scope_update on "app_private"."stock_bins" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_bins";
create policy bsb_tenant_scope_delete on "app_private"."stock_bins" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_lots";
create policy bsb_tenant_scope_select on "app_private"."stock_lots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_lots";
create policy bsb_tenant_scope_insert on "app_private"."stock_lots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_lots";
create policy bsb_tenant_scope_update on "app_private"."stock_lots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_lots";
create policy bsb_tenant_scope_delete on "app_private"."stock_lots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_serials";
create policy bsb_tenant_scope_select on "app_private"."stock_serials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_serials";
create policy bsb_tenant_scope_insert on "app_private"."stock_serials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_serials";
create policy bsb_tenant_scope_update on "app_private"."stock_serials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_serials";
create policy bsb_tenant_scope_delete on "app_private"."stock_serials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_buckets";
create policy bsb_tenant_scope_select on "app_private"."stock_buckets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_buckets";
create policy bsb_tenant_scope_insert on "app_private"."stock_buckets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_buckets";
create policy bsb_tenant_scope_update on "app_private"."stock_buckets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_buckets";
create policy bsb_tenant_scope_delete on "app_private"."stock_buckets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "app_private"."stock_allocations";
create policy bsb_tenant_scope_select on "app_private"."stock_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."stock_allocations";
create policy bsb_tenant_scope_insert on "app_private"."stock_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."stock_allocations";
create policy bsb_tenant_scope_update on "app_private"."stock_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."stock_allocations";
create policy bsb_tenant_scope_delete on "app_private"."stock_allocations" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:d6e6d2650c4d87bfa05c60fe58f7687d236314481b293310be3c0c3870113b3d
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

create table if not exists "better_supabase"."inventory_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual')),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
alter table "better_supabase"."inventory_locations" enable row level security;
revoke all on "better_supabase"."inventory_locations" from public, anon, authenticated;
grant select on "better_supabase"."inventory_locations" to authenticated;
grant all on "better_supabase"."inventory_locations" to service_role;
drop policy if exists inventory_locations_read on "better_supabase"."inventory_locations";
create policy inventory_locations_read on "better_supabase"."inventory_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_levels" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "on_hand" numeric(20, 6) not null default 0,
  "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0),
  "held" numeric(20, 6) not null default 0 check ("held" >= 0),
  "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0),
  "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored,
  "reorder_point" numeric(20, 6) check ("reorder_point" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "location_id")
);
create index if not exists stock_levels_location_idx on "better_supabase"."stock_levels" ("location_id");
alter table "better_supabase"."stock_levels" enable row level security;
revoke all on "better_supabase"."stock_levels" from public, anon, authenticated;
grant select on "better_supabase"."stock_levels" to authenticated;
grant all on "better_supabase"."stock_levels" to service_role;
drop policy if exists stock_levels_read on "better_supabase"."stock_levels";
create policy stock_levels_read on "better_supabase"."stock_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_reservations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on "better_supabase"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "better_supabase"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "better_supabase"."stock_reservations" ("location_id");
alter table "better_supabase"."stock_reservations" enable row level security;
revoke all on "better_supabase"."stock_reservations" from public, anon, authenticated;
grant select on "better_supabase"."stock_reservations" to authenticated;
grant all on "better_supabase"."stock_reservations" to service_role;
drop policy if exists stock_reservations_read on "better_supabase"."stock_reservations";
create policy stock_reservations_read on "better_supabase"."stock_reservations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "from_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "to_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled')),
  "note" text,
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "received_at" timestamptz,
  check ("from_location_id" <> "to_location_id")
);
create index if not exists stock_transfers_from_idx on "better_supabase"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "better_supabase"."stock_transfers" ("to_location_id");
alter table "better_supabase"."stock_transfers" enable row level security;
revoke all on "better_supabase"."stock_transfers" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfers" to authenticated;
grant all on "better_supabase"."stock_transfers" to service_role;
drop policy if exists stock_transfers_read on "better_supabase"."stock_transfers";
create policy stock_transfers_read on "better_supabase"."stock_transfers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfer_lines" (
  "tenant_id" uuid not null,
  "transfer_id" uuid not null references "better_supabase"."stock_transfers" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  "detail" jsonb,
  primary key ("transfer_id", "variant_id")
);
create index if not exists stock_transfer_lines_variant_idx on "better_supabase"."stock_transfer_lines" ("variant_id");
alter table "better_supabase"."stock_transfer_lines" enable row level security;
revoke all on "better_supabase"."stock_transfer_lines" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfer_lines" to authenticated;
grant all on "better_supabase"."stock_transfer_lines" to service_role;
drop policy if exists stock_transfer_lines_read on "better_supabase"."stock_transfer_lines";
create policy stock_transfer_lines_read on "better_supabase"."stock_transfer_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "supplier_type" text,
  "supplier_id" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "expected_at" timestamptz,
  "note" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "placed_at" timestamptz,
  check (("supplier_type" is null) = ("supplier_id" is null))
);
create index if not exists purchase_orders_location_idx on "better_supabase"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "better_supabase"."purchase_orders" ("tenant_id", "status");
alter table "better_supabase"."purchase_orders" enable row level security;
revoke all on "better_supabase"."purchase_orders" from public, anon, authenticated;
grant select on "better_supabase"."purchase_orders" to authenticated;
grant all on "better_supabase"."purchase_orders" to service_role;
drop policy if exists purchase_orders_read on "better_supabase"."purchase_orders";
create policy purchase_orders_read on "better_supabase"."purchase_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "purchase_order_id" uuid not null references "better_supabase"."purchase_orders" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity_ordered" numeric(20, 6) not null check ("quantity_ordered" > 0),
  "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
  "unit_cost" bigint not null check ("unit_cost" >= 0),
  unique ("purchase_order_id", "variant_id")
);
create index if not exists purchase_order_lines_variant_idx on "better_supabase"."purchase_order_lines" ("variant_id");
alter table "better_supabase"."purchase_order_lines" enable row level security;
revoke all on "better_supabase"."purchase_order_lines" from public, anon, authenticated;
grant select on "better_supabase"."purchase_order_lines" to authenticated;
grant all on "better_supabase"."purchase_order_lines" to service_role;
drop policy if exists purchase_order_lines_read on "better_supabase"."purchase_order_lines";
create policy purchase_order_lines_read on "better_supabase"."purchase_order_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_items" (
  "variant_id" uuid primary key references "better_supabase"."product_variants" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$'),
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial')),
  "tracks_expiry" boolean not null default false,
  "costing" text not null default 'none' check ("costing" in ('none', 'average')),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "average_cost" numeric(24, 6) check ("average_cost" >= 0),
  "updated_at" timestamptz not null default now(),
  check ("tracking" <> 'serial' or "scale" = 0),
  check ("costing" = 'none' or "currency" is not null)
);
create index if not exists stock_items_tenant_idx on "better_supabase"."stock_items" ("tenant_id");
alter table "better_supabase"."stock_items" enable row level security;
revoke all on "better_supabase"."stock_items" from public, anon, authenticated;
grant select on "better_supabase"."stock_items" to authenticated;
grant all on "better_supabase"."stock_items" to service_role;
drop policy if exists stock_items_read on "better_supabase"."stock_items";
create policy stock_items_read on "better_supabase"."stock_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_bins" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  "name" text check (length("name") between 1 and 200),
  "hold" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("location_id", "code")
);
create index if not exists stock_bins_tenant_idx on "better_supabase"."stock_bins" ("tenant_id");
alter table "better_supabase"."stock_bins" enable row level security;
revoke all on "better_supabase"."stock_bins" from public, anon, authenticated;
grant select on "better_supabase"."stock_bins" to authenticated;
grant all on "better_supabase"."stock_bins" to service_role;
drop policy if exists stock_bins_read on "better_supabase"."stock_bins";
create policy stock_bins_read on "better_supabase"."stock_bins"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_lots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "code" text not null check (length("code") between 1 and 100),
  "expires_on" date,
  "created_at" timestamptz not null default now(),
  unique ("variant_id", "code")
);
create index if not exists stock_lots_expiry_idx on "better_supabase"."stock_lots" ("tenant_id", "expires_on") where "expires_on" is not null;
alter table "better_supabase"."stock_lots" enable row level security;
revoke all on "better_supabase"."stock_lots" from public, anon, authenticated;
grant select on "better_supabase"."stock_lots" to authenticated;
grant all on "better_supabase"."stock_lots" to service_role;
drop policy if exists stock_lots_read on "better_supabase"."stock_lots";
create policy stock_lots_read on "better_supabase"."stock_lots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_serials" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "serial" text not null check (length("serial") between 1 and 100),
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete set null,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete set null,
  "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped')),
  "movement_id" uuid,
  "updated_at" timestamptz not null default now(),
  unique ("variant_id", "serial")
);
create index if not exists stock_serials_location_id_idx on "better_supabase"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "better_supabase"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "better_supabase"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "better_supabase"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "better_supabase"."stock_serials" ("tenant_id");
alter table "better_supabase"."stock_serials" enable row level security;
revoke all on "better_supabase"."stock_serials" from public, anon, authenticated;
grant select on "better_supabase"."stock_serials" to authenticated;
grant all on "better_supabase"."stock_serials" to service_role;
drop policy if exists stock_serials_read on "better_supabase"."stock_serials";
create policy stock_serials_read on "better_supabase"."stock_serials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_buckets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete restrict,
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict,
  "on_hand" numeric(20, 6) not null default 0,
  "updated_at" timestamptz not null default now(),
  check ("bin_id" is not null or "lot_id" is not null),
  unique nulls not distinct ("variant_id", "location_id", "bin_id", "lot_id")
);
create index if not exists stock_buckets_location_idx on "better_supabase"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "better_supabase"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "better_supabase"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "better_supabase"."stock_buckets" ("tenant_id");
alter table "better_supabase"."stock_buckets" enable row level security;
revoke all on "better_supabase"."stock_buckets" from public, anon, authenticated;
grant select on "better_supabase"."stock_buckets" to authenticated;
grant all on "better_supabase"."stock_buckets" to service_role;
drop policy if exists stock_buckets_read on "better_supabase"."stock_buckets";
create policy stock_buckets_read on "better_supabase"."stock_buckets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "line_id" text,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0),
  "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0),
  "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored,
  "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("allocated" + "fulfilled" <= "quantity")
);
create index if not exists stock_allocations_document_idx on "better_supabase"."stock_allocations" ("tenant_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "better_supabase"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "better_supabase"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "better_supabase"."stock_allocations" ("variant_id");
alter table "better_supabase"."stock_allocations" enable row level security;
revoke all on "better_supabase"."stock_allocations" from public, anon, authenticated;
grant select on "better_supabase"."stock_allocations" to authenticated;
grant all on "better_supabase"."stock_allocations" to service_role;
drop policy if exists stock_allocations_read on "better_supabase"."stock_allocations";
create policy stock_allocations_read on "better_supabase"."stock_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    null;
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "better_supabase"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."stock_items"%rowtype;
  v_old "better_supabase"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "better_supabase"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."tenant_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "better_supabase"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "better_supabase"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."stock_bins" ("tenant_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "better_supabase"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "better_supabase"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "better_supabase"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "better_supabase"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "better_supabase"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "better_supabase"."stock_lots" as x ("tenant_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "better_supabase"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "better_supabase"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "better_supabase"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "better_supabase"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "better_supabase"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "better_supabase"."stock_buckets" y
  left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
  left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "better_supabase"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "better_supabase"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "better_supabase"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "better_supabase"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "better_supabase"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "better_supabase"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "better_supabase"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "better_supabase"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."tenant_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."stock_valuation"(uuid) from public, anon;
grant execute on function "better_supabase"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "better_supabase"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "better_supabase"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    null;
  end loop;
  if v_total > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "better_supabase"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "better_supabase"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."tenant_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    left join "better_supabase"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."tenant_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location and y."tenant_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "better_supabase"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "better_supabase"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "better_supabase"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "better_supabase"."stock_allocations" x
    where x."tenant_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    null;
    if v_row.allocated > 0 then
      perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "better_supabase"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "better_supabase"."stock_allocations" x where x."tenant_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "better_supabase"."save_location"(uuid, uuid, text, text, text);
create or replace function "better_supabase"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "better_supabase"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "better_supabase"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_location"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "better_supabase"."count_stock"(uuid, uuid, integer, text);
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "better_supabase"."set_reorder_point"(uuid, uuid, integer);
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "better_supabase"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  null;
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "better_supabase"."commit_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "better_supabase"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "better_supabase"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "better_supabase"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "better_supabase"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "better_supabase"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "better_supabase"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "better_supabase"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "better_supabase"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "better_supabase"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "better_supabase"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "better_supabase"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."place_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "better_supabase"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  null;
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "better_supabase"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_purchase_order"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_select on "better_supabase"."inventory_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
create policy bsb_tenant_scope_select on "better_supabase"."stock_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
create policy bsb_tenant_scope_update on "better_supabase"."stock_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_select on "better_supabase"."stock_bins" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_bins" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_update on "better_supabase"."stock_bins" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_bins" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_select on "better_supabase"."stock_serials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_serials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_update on "better_supabase"."stock_serials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_serials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_select on "better_supabase"."stock_buckets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_buckets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_update on "better_supabase"."stock_buckets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_buckets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_allocations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.inventory.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_location"(uuid, uuid, text, text, text);
drop function if exists "api"."adjust_stock"(uuid, uuid, integer, text, text);
drop function if exists "api"."count_stock"(uuid, uuid, integer, text);
drop function if exists "api"."set_reorder_point"(uuid, uuid, integer);
drop function if exists "api"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);

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

create or replace function "api"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_stock_item"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "api"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

create or replace function "api"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_bin"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "api"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

create or replace function "api"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_lot"($1, $2, $3) $$;
revoke execute on function "api"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "api"."save_lot"(uuid, text, date) to authenticated, service_role;

create or replace function "api"."stock_detail"(variant uuid, location uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."stock_detail"($1, $2) $$;
revoke execute on function "api"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "api"."stock_detail"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."expiring_lots"(tenant uuid, before date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expiring_lots"($1, $2) $$;
revoke execute on function "api"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "api"."expiring_lots"(uuid, date) to authenticated, service_role;

create or replace function "api"."expire_lots"(tenant uuid, as_of date)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_lots"($1, $2) $$;
revoke execute on function "api"."expire_lots"(uuid, date) from public, anon;
grant execute on function "api"."expire_lots"(uuid, date) to authenticated, service_role;

create or replace function "api"."stock_valuation"(variant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."stock_valuation"($1) $$;
revoke execute on function "api"."stock_valuation"(uuid) from public, anon;
grant execute on function "api"."stock_valuation"(uuid) to authenticated, service_role;

create or replace function "api"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."allocate_stock"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "api"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fulfill_allocation"($1, $2, $3) $$;
revoke execute on function "api"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "api"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

create or replace function "api"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_allocation"($1, $2, $3) $$;
revoke execute on function "api"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "api"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

create or replace function "api"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_allocations"($1, $2, $3) $$;
revoke execute on function "api"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "api"."release_allocations"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_allocations"($1, $2, $3) $$;
revoke execute on function "api"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "api"."list_allocations"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_location"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."set_location_active"(location uuid, active boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_location_active"($1, $2) $$;
revoke execute on function "api"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "api"."set_location_active"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_location"(location uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_location"($1) $$;
revoke execute on function "api"."delete_location"(uuid) from public, anon;
grant execute on function "api"."delete_location"(uuid) to authenticated, service_role;

create or replace function "api"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."adjust_stock"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "api"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."count_stock"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "api"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

create or replace function "api"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_reorder_point"($1, $2, $3) $$;
revoke execute on function "api"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "api"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

create or replace function "api"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reserve_stock"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "api"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."commit_reservation"(reservation uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."commit_reservation"($1) $$;
revoke execute on function "api"."commit_reservation"(uuid) from public, anon;
grant execute on function "api"."commit_reservation"(uuid) to authenticated, service_role;

create or replace function "api"."release_reservation"(reservation uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_reservation"($1) $$;
revoke execute on function "api"."release_reservation"(uuid) from public, anon;
grant execute on function "api"."release_reservation"(uuid) to authenticated, service_role;

create or replace function "api"."expire_reservations"(max_rows integer)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_reservations"($1) $$;
revoke execute on function "api"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "api"."expire_reservations"(integer) to service_role;

create or replace function "api"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_transfer"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "api"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."ship_transfer"(transfer uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ship_transfer"($1) $$;
revoke execute on function "api"."ship_transfer"(uuid) from public, anon;
grant execute on function "api"."ship_transfer"(uuid) to authenticated, service_role;

create or replace function "api"."receive_transfer"(transfer uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."receive_transfer"($1) $$;
revoke execute on function "api"."receive_transfer"(uuid) from public, anon;
grant execute on function "api"."receive_transfer"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_transfer"(transfer uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_transfer"($1) $$;
revoke execute on function "api"."cancel_transfer"(uuid) from public, anon;
grant execute on function "api"."cancel_transfer"(uuid) to authenticated, service_role;

create or replace function "api"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_purchase_order"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "api"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

create or replace function "api"."place_purchase_order"(purchase_order uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."place_purchase_order"($1) $$;
revoke execute on function "api"."place_purchase_order"(uuid) from public, anon;
grant execute on function "api"."place_purchase_order"(uuid) to authenticated, service_role;

create or replace function "api"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."receive_purchase_order"($1, $2) $$;
revoke execute on function "api"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "api"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_purchase_order"($1) $$;
revoke execute on function "api"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "api"."cancel_purchase_order"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:fa3342da2171355fe72b934e64b5498efbee212e97aa8a27a33acb558364e5ea
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

-- better_supabase.inventory_locations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."inventory_locations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."inventory_locations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."inventory_locations" add column if not exists "code" text;
alter table "better_supabase"."inventory_locations" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."inventory_locations" add column if not exists "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual'));
alter table "better_supabase"."inventory_locations" add column if not exists "active" boolean not null default true;
alter table "better_supabase"."inventory_locations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."inventory_locations" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."inventory_locations" enable row level security;
grant select on "better_supabase"."inventory_locations" to authenticated;
grant all on "better_supabase"."inventory_locations" to service_role;
drop policy if exists bsb_inventory_locations_select on "better_supabase"."inventory_locations";
create policy bsb_inventory_locations_select on "better_supabase"."inventory_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_levels is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_levels" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_levels" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_levels" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_levels" add column if not exists "on_hand" numeric(20, 6) not null default 0;
alter table "better_supabase"."stock_levels" add column if not exists "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0);
alter table "better_supabase"."stock_levels" add column if not exists "held" numeric(20, 6) not null default 0 check ("held" >= 0);
alter table "better_supabase"."stock_levels" add column if not exists "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0);
alter table "better_supabase"."stock_levels" add column if not exists "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored;
alter table "better_supabase"."stock_levels" add column if not exists "reorder_point" numeric(20, 6) check ("reorder_point" >= 0);
alter table "better_supabase"."stock_levels" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_levels_location_idx on "better_supabase"."stock_levels" ("location_id");
alter table "better_supabase"."stock_levels" enable row level security;
grant select on "better_supabase"."stock_levels" to authenticated;
grant all on "better_supabase"."stock_levels" to service_role;
drop policy if exists bsb_stock_levels_select on "better_supabase"."stock_levels";
create policy bsb_stock_levels_select on "better_supabase"."stock_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_reservations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_reservations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_reservations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_reservations" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_reservations" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_reservations" add column if not exists "quantity" numeric(20, 6) check ("quantity" > 0);
alter table "better_supabase"."stock_reservations" add column if not exists "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired'));
alter table "better_supabase"."stock_reservations" add column if not exists "reference_type" text;
alter table "better_supabase"."stock_reservations" add column if not exists "reference_id" text;
alter table "better_supabase"."stock_reservations" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."stock_reservations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."stock_reservations" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_reservations_active_idx on "better_supabase"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "better_supabase"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "better_supabase"."stock_reservations" ("location_id");
alter table "better_supabase"."stock_reservations" enable row level security;
grant select on "better_supabase"."stock_reservations" to authenticated;
grant all on "better_supabase"."stock_reservations" to service_role;
drop policy if exists bsb_stock_reservations_select on "better_supabase"."stock_reservations";
create policy bsb_stock_reservations_select on "better_supabase"."stock_reservations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_transfers is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_transfers" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_transfers" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_transfers" add column if not exists "from_location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_transfers" add column if not exists "to_location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_transfers" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled'));
alter table "better_supabase"."stock_transfers" add column if not exists "note" text;
alter table "better_supabase"."stock_transfers" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."stock_transfers" add column if not exists "shipped_at" timestamptz;
alter table "better_supabase"."stock_transfers" add column if not exists "received_at" timestamptz;
create index if not exists stock_transfers_from_idx on "better_supabase"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "better_supabase"."stock_transfers" ("to_location_id");
alter table "better_supabase"."stock_transfers" enable row level security;
grant select on "better_supabase"."stock_transfers" to authenticated;
grant all on "better_supabase"."stock_transfers" to service_role;
drop policy if exists bsb_stock_transfers_select on "better_supabase"."stock_transfers";
create policy bsb_stock_transfers_select on "better_supabase"."stock_transfers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_transfer_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_transfer_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_transfer_lines" add column if not exists "transfer_id" uuid references "better_supabase"."stock_transfers" ("id") on delete cascade;
alter table "better_supabase"."stock_transfer_lines" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_transfer_lines" add column if not exists "quantity" numeric(20, 6) check ("quantity" > 0);
alter table "better_supabase"."stock_transfer_lines" add column if not exists "detail" jsonb;
create index if not exists stock_transfer_lines_variant_idx on "better_supabase"."stock_transfer_lines" ("variant_id");
alter table "better_supabase"."stock_transfer_lines" enable row level security;
grant select on "better_supabase"."stock_transfer_lines" to authenticated;
grant all on "better_supabase"."stock_transfer_lines" to service_role;
drop policy if exists bsb_stock_transfer_lines_select on "better_supabase"."stock_transfer_lines";
create policy bsb_stock_transfer_lines_select on "better_supabase"."stock_transfer_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.purchase_orders is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."purchase_orders" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."purchase_orders" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."purchase_orders" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."purchase_orders" add column if not exists "supplier_type" text;
alter table "better_supabase"."purchase_orders" add column if not exists "supplier_id" text;
alter table "better_supabase"."purchase_orders" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled'));
alter table "better_supabase"."purchase_orders" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."purchase_orders" add column if not exists "expected_at" timestamptz;
alter table "better_supabase"."purchase_orders" add column if not exists "note" text;
alter table "better_supabase"."purchase_orders" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."purchase_orders" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."purchase_orders" add column if not exists "placed_at" timestamptz;
create index if not exists purchase_orders_location_idx on "better_supabase"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "better_supabase"."purchase_orders" ("tenant_id", "status");
alter table "better_supabase"."purchase_orders" enable row level security;
grant select on "better_supabase"."purchase_orders" to authenticated;
grant all on "better_supabase"."purchase_orders" to service_role;
drop policy if exists bsb_purchase_orders_select on "better_supabase"."purchase_orders";
create policy bsb_purchase_orders_select on "better_supabase"."purchase_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.purchase_order_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."purchase_order_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."purchase_order_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."purchase_order_lines" add column if not exists "purchase_order_id" uuid references "better_supabase"."purchase_orders" ("id") on delete cascade;
alter table "better_supabase"."purchase_order_lines" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."purchase_order_lines" add column if not exists "quantity_ordered" numeric(20, 6) check ("quantity_ordered" > 0);
alter table "better_supabase"."purchase_order_lines" add column if not exists "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered");
alter table "better_supabase"."purchase_order_lines" add column if not exists "unit_cost" bigint check ("unit_cost" >= 0);
create index if not exists purchase_order_lines_variant_idx on "better_supabase"."purchase_order_lines" ("variant_id");
alter table "better_supabase"."purchase_order_lines" enable row level security;
grant select on "better_supabase"."purchase_order_lines" to authenticated;
grant all on "better_supabase"."purchase_order_lines" to service_role;
drop policy if exists bsb_purchase_order_lines_select on "better_supabase"."purchase_order_lines";
create policy bsb_purchase_order_lines_select on "better_supabase"."purchase_order_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_items is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_items" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_items" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_items" add column if not exists "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$');
alter table "better_supabase"."stock_items" add column if not exists "scale" smallint not null default 0 check ("scale" between 0 and 6);
alter table "better_supabase"."stock_items" add column if not exists "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial'));
alter table "better_supabase"."stock_items" add column if not exists "tracks_expiry" boolean not null default false;
alter table "better_supabase"."stock_items" add column if not exists "costing" text not null default 'none' check ("costing" in ('none', 'average'));
alter table "better_supabase"."stock_items" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."stock_items" add column if not exists "average_cost" numeric(24, 6) check ("average_cost" >= 0);
alter table "better_supabase"."stock_items" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_items_tenant_idx on "better_supabase"."stock_items" ("tenant_id");
alter table "better_supabase"."stock_items" enable row level security;
grant select on "better_supabase"."stock_items" to authenticated;
grant all on "better_supabase"."stock_items" to service_role;
drop policy if exists bsb_stock_items_select on "better_supabase"."stock_items";
create policy bsb_stock_items_select on "better_supabase"."stock_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_bins is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_bins" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_bins" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_bins" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_bins" add column if not exists "code" text check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$');
alter table "better_supabase"."stock_bins" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."stock_bins" add column if not exists "hold" boolean not null default false;
alter table "better_supabase"."stock_bins" add column if not exists "active" boolean not null default true;
alter table "better_supabase"."stock_bins" add column if not exists "created_at" timestamptz not null default now();
create index if not exists stock_bins_tenant_idx on "better_supabase"."stock_bins" ("tenant_id");
alter table "better_supabase"."stock_bins" enable row level security;
grant select on "better_supabase"."stock_bins" to authenticated;
grant all on "better_supabase"."stock_bins" to service_role;
drop policy if exists bsb_stock_bins_select on "better_supabase"."stock_bins";
create policy bsb_stock_bins_select on "better_supabase"."stock_bins"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_lots is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_lots" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_lots" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_lots" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_lots" add column if not exists "code" text check (length("code") between 1 and 100);
alter table "better_supabase"."stock_lots" add column if not exists "expires_on" date;
alter table "better_supabase"."stock_lots" add column if not exists "created_at" timestamptz not null default now();
create index if not exists stock_lots_expiry_idx on "better_supabase"."stock_lots" ("tenant_id", "expires_on") where "expires_on" is not null;
alter table "better_supabase"."stock_lots" enable row level security;
grant select on "better_supabase"."stock_lots" to authenticated;
grant all on "better_supabase"."stock_lots" to service_role;
drop policy if exists bsb_stock_lots_select on "better_supabase"."stock_lots";
create policy bsb_stock_lots_select on "better_supabase"."stock_lots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_serials is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_serials" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_serials" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_serials" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_serials" add column if not exists "serial" text check (length("serial") between 1 and 100);
alter table "better_supabase"."stock_serials" add column if not exists "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null;
alter table "better_supabase"."stock_serials" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete set null;
alter table "better_supabase"."stock_serials" add column if not exists "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete set null;
alter table "better_supabase"."stock_serials" add column if not exists "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped'));
alter table "better_supabase"."stock_serials" add column if not exists "movement_id" uuid;
alter table "better_supabase"."stock_serials" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_serials_location_id_idx on "better_supabase"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "better_supabase"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "better_supabase"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "better_supabase"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "better_supabase"."stock_serials" ("tenant_id");
alter table "better_supabase"."stock_serials" enable row level security;
grant select on "better_supabase"."stock_serials" to authenticated;
grant all on "better_supabase"."stock_serials" to service_role;
drop policy if exists bsb_stock_serials_select on "better_supabase"."stock_serials";
create policy bsb_stock_serials_select on "better_supabase"."stock_serials"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_buckets is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_buckets" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_buckets" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_buckets" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_buckets" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_buckets" add column if not exists "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete restrict;
alter table "better_supabase"."stock_buckets" add column if not exists "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict;
alter table "better_supabase"."stock_buckets" add column if not exists "on_hand" numeric(20, 6) not null default 0;
alter table "better_supabase"."stock_buckets" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_buckets_location_idx on "better_supabase"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "better_supabase"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "better_supabase"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "better_supabase"."stock_buckets" ("tenant_id");
alter table "better_supabase"."stock_buckets" enable row level security;
grant select on "better_supabase"."stock_buckets" to authenticated;
grant all on "better_supabase"."stock_buckets" to service_role;
drop policy if exists bsb_stock_buckets_select on "better_supabase"."stock_buckets";
create policy bsb_stock_buckets_select on "better_supabase"."stock_buckets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

-- better_supabase.stock_allocations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."stock_allocations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."stock_allocations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."stock_allocations" add column if not exists "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade;
alter table "better_supabase"."stock_allocations" add column if not exists "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete cascade;
alter table "better_supabase"."stock_allocations" add column if not exists "document_type" text check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."stock_allocations" add column if not exists "document_id" text check (length("document_id") between 1 and 200);
alter table "better_supabase"."stock_allocations" add column if not exists "line_id" text;
alter table "better_supabase"."stock_allocations" add column if not exists "quantity" numeric(20, 6) check ("quantity" > 0);
alter table "better_supabase"."stock_allocations" add column if not exists "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0);
alter table "better_supabase"."stock_allocations" add column if not exists "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0);
alter table "better_supabase"."stock_allocations" add column if not exists "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored;
alter table "better_supabase"."stock_allocations" add column if not exists "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released'));
alter table "better_supabase"."stock_allocations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."stock_allocations" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists stock_allocations_document_idx on "better_supabase"."stock_allocations" ("tenant_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "better_supabase"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "better_supabase"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "better_supabase"."stock_allocations" ("variant_id");
alter table "better_supabase"."stock_allocations" enable row level security;
grant select on "better_supabase"."stock_allocations" to authenticated;
grant all on "better_supabase"."stock_allocations" to service_role;
drop policy if exists bsb_stock_allocations_select on "better_supabase"."stock_allocations";
create policy bsb_stock_allocations_select on "better_supabase"."stock_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    null;
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "better_supabase"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."stock_items"%rowtype;
  v_old "better_supabase"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "better_supabase"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."tenant_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "better_supabase"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "better_supabase"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."stock_bins" ("tenant_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "better_supabase"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "better_supabase"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "better_supabase"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "better_supabase"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "better_supabase"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "better_supabase"."stock_lots" as x ("tenant_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "better_supabase"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "better_supabase"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "better_supabase"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "better_supabase"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "better_supabase"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "better_supabase"."stock_buckets" y
  left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
  left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "better_supabase"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "better_supabase"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "better_supabase"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "better_supabase"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."tenant_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "better_supabase"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "better_supabase"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."tenant_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "better_supabase"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "better_supabase"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."tenant_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."stock_valuation"(uuid) from public, anon;
grant execute on function "better_supabase"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "better_supabase"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "better_supabase"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    null;
  end loop;
  if v_total > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "better_supabase"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "better_supabase"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."tenant_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    left join "better_supabase"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."tenant_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location and y."tenant_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_allocations" as x ("tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "better_supabase"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "better_supabase"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "better_supabase"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "better_supabase"."stock_allocations" x
    where x."tenant_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    null;
    if v_row.allocated > 0 then
      perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "better_supabase"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "better_supabase"."stock_allocations" x where x."tenant_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "better_supabase"."save_location"(uuid, uuid, text, text, text);
create or replace function "better_supabase"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "better_supabase"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "better_supabase"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_location"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "better_supabase"."count_stock"(uuid, uuid, integer, text);
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "better_supabase"."set_reorder_point"(uuid, uuid, integer);
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "better_supabase"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  null;
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "better_supabase"."commit_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "better_supabase"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "better_supabase"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "better_supabase"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."tenant_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "better_supabase"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "better_supabase"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "better_supabase"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "better_supabase"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "better_supabase"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "better_supabase"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "better_supabase"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "better_supabase"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."place_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "better_supabase"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = better_supabase.as_column_type(v_status, (null::"better_supabase"."purchase_orders")."status"), "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  null;
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "better_supabase"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_purchase_order"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_select on "better_supabase"."inventory_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
create policy bsb_tenant_scope_select on "better_supabase"."stock_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
create policy bsb_tenant_scope_update on "better_supabase"."stock_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_select on "better_supabase"."stock_bins" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_bins" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_update on "better_supabase"."stock_bins" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_bins" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_select on "better_supabase"."stock_serials" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_serials" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_update on "better_supabase"."stock_serials" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_serials" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_select on "better_supabase"."stock_buckets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_buckets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_update on "better_supabase"."stock_buckets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_buckets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_allocations" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@3 managed
-- @bsb-hash sha256:9f0863f57b2f44e1515851c442749126c9aa900072c68e745e8c4314d7348c34
-- Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.

create table if not exists "better_supabase"."inventory_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "code" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'warehouse' check ("kind" in ('warehouse', 'store', 'virtual')),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "code")
);
alter table "better_supabase"."inventory_locations" enable row level security;
revoke all on "better_supabase"."inventory_locations" from public, anon, authenticated;
grant select on "better_supabase"."inventory_locations" to authenticated;
grant all on "better_supabase"."inventory_locations" to service_role;
drop policy if exists inventory_locations_read on "better_supabase"."inventory_locations";
create policy inventory_locations_read on "better_supabase"."inventory_locations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_levels" (
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "on_hand" numeric(20, 6) not null default 0,
  "reserved" numeric(20, 6) not null default 0 check ("reserved" >= 0),
  "held" numeric(20, 6) not null default 0 check ("held" >= 0),
  "incoming" numeric(20, 6) not null default 0 check ("incoming" >= 0),
  "available" numeric(20, 6) generated always as ("on_hand" - "reserved" - "held") stored,
  "reorder_point" numeric(20, 6) check ("reorder_point" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "location_id")
);
create index if not exists stock_levels_location_idx on "better_supabase"."stock_levels" ("location_id");
alter table "better_supabase"."stock_levels" enable row level security;
revoke all on "better_supabase"."stock_levels" from public, anon, authenticated;
grant select on "better_supabase"."stock_levels" to authenticated;
grant all on "better_supabase"."stock_levels" to service_role;
drop policy if exists stock_levels_read on "better_supabase"."stock_levels";
create policy stock_levels_read on "better_supabase"."stock_levels"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_reservations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'committed', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on "better_supabase"."stock_reservations" ("expires_at") where "status" = 'active';
create index if not exists stock_reservations_level_idx on "better_supabase"."stock_reservations" ("variant_id", "location_id");
create index if not exists stock_reservations_location_idx on "better_supabase"."stock_reservations" ("location_id");
alter table "better_supabase"."stock_reservations" enable row level security;
revoke all on "better_supabase"."stock_reservations" from public, anon, authenticated;
grant select on "better_supabase"."stock_reservations" to authenticated;
grant all on "better_supabase"."stock_reservations" to service_role;
drop policy if exists stock_reservations_read on "better_supabase"."stock_reservations";
create policy stock_reservations_read on "better_supabase"."stock_reservations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfers" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "from_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "to_location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_transit', 'received', 'cancelled')),
  "note" text,
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "received_at" timestamptz,
  check ("from_location_id" <> "to_location_id")
);
create index if not exists stock_transfers_from_idx on "better_supabase"."stock_transfers" ("from_location_id");
create index if not exists stock_transfers_to_idx on "better_supabase"."stock_transfers" ("to_location_id");
alter table "better_supabase"."stock_transfers" enable row level security;
revoke all on "better_supabase"."stock_transfers" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfers" to authenticated;
grant all on "better_supabase"."stock_transfers" to service_role;
drop policy if exists stock_transfers_read on "better_supabase"."stock_transfers";
create policy stock_transfers_read on "better_supabase"."stock_transfers"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_transfer_lines" (
  "org_id" uuid not null,
  "transfer_id" uuid not null references "better_supabase"."stock_transfers" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  "detail" jsonb,
  primary key ("transfer_id", "variant_id")
);
create index if not exists stock_transfer_lines_variant_idx on "better_supabase"."stock_transfer_lines" ("variant_id");
alter table "better_supabase"."stock_transfer_lines" enable row level security;
revoke all on "better_supabase"."stock_transfer_lines" from public, anon, authenticated;
grant select on "better_supabase"."stock_transfer_lines" to authenticated;
grant all on "better_supabase"."stock_transfer_lines" to service_role;
drop policy if exists stock_transfer_lines_read on "better_supabase"."stock_transfer_lines";
create policy stock_transfer_lines_read on "better_supabase"."stock_transfer_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "supplier_type" text,
  "supplier_id" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "expected_at" timestamptz,
  "note" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "placed_at" timestamptz,
  check (("supplier_type" is null) = ("supplier_id" is null))
);
create index if not exists purchase_orders_location_idx on "better_supabase"."purchase_orders" ("location_id");
create index if not exists purchase_orders_status_idx on "better_supabase"."purchase_orders" ("org_id", "status");
alter table "better_supabase"."purchase_orders" enable row level security;
revoke all on "better_supabase"."purchase_orders" from public, anon, authenticated;
grant select on "better_supabase"."purchase_orders" to authenticated;
grant all on "better_supabase"."purchase_orders" to service_role;
drop policy if exists purchase_orders_read on "better_supabase"."purchase_orders";
create policy purchase_orders_read on "better_supabase"."purchase_orders"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."purchase_order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "purchase_order_id" uuid not null references "better_supabase"."purchase_orders" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity_ordered" numeric(20, 6) not null check ("quantity_ordered" > 0),
  "quantity_received" numeric(20, 6) not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
  "unit_cost" bigint not null check ("unit_cost" >= 0),
  unique ("purchase_order_id", "variant_id")
);
create index if not exists purchase_order_lines_variant_idx on "better_supabase"."purchase_order_lines" ("variant_id");
alter table "better_supabase"."purchase_order_lines" enable row level security;
revoke all on "better_supabase"."purchase_order_lines" from public, anon, authenticated;
grant select on "better_supabase"."purchase_order_lines" to authenticated;
grant all on "better_supabase"."purchase_order_lines" to service_role;
drop policy if exists purchase_order_lines_read on "better_supabase"."purchase_order_lines";
create policy purchase_order_lines_read on "better_supabase"."purchase_order_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_items" (
  "variant_id" uuid primary key references "better_supabase"."product_variants" ("id") on delete cascade,
  "org_id" uuid not null,
  "unit" text not null default 'item' check ("unit" ~ '^[a-z][a-z0-9_]{0,31}$'),
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "tracking" text not null default 'none' check ("tracking" in ('none', 'lot', 'serial')),
  "tracks_expiry" boolean not null default false,
  "costing" text not null default 'none' check ("costing" in ('none', 'average')),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "average_cost" numeric(24, 6) check ("average_cost" >= 0),
  "updated_at" timestamptz not null default now(),
  check ("tracking" <> 'serial' or "scale" = 0),
  check ("costing" = 'none' or "currency" is not null)
);
create index if not exists stock_items_tenant_idx on "better_supabase"."stock_items" ("org_id");
alter table "better_supabase"."stock_items" enable row level security;
revoke all on "better_supabase"."stock_items" from public, anon, authenticated;
grant select on "better_supabase"."stock_items" to authenticated;
grant all on "better_supabase"."stock_items" to service_role;
drop policy if exists stock_items_read on "better_supabase"."stock_items";
create policy stock_items_read on "better_supabase"."stock_items"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_bins" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  "name" text check (length("name") between 1 and 200),
  "hold" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("location_id", "code")
);
create index if not exists stock_bins_tenant_idx on "better_supabase"."stock_bins" ("org_id");
alter table "better_supabase"."stock_bins" enable row level security;
revoke all on "better_supabase"."stock_bins" from public, anon, authenticated;
grant select on "better_supabase"."stock_bins" to authenticated;
grant all on "better_supabase"."stock_bins" to service_role;
drop policy if exists stock_bins_read on "better_supabase"."stock_bins";
create policy stock_bins_read on "better_supabase"."stock_bins"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_lots" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "code" text not null check (length("code") between 1 and 100),
  "expires_on" date,
  "created_at" timestamptz not null default now(),
  unique ("variant_id", "code")
);
create index if not exists stock_lots_expiry_idx on "better_supabase"."stock_lots" ("org_id", "expires_on") where "expires_on" is not null;
alter table "better_supabase"."stock_lots" enable row level security;
revoke all on "better_supabase"."stock_lots" from public, anon, authenticated;
grant select on "better_supabase"."stock_lots" to authenticated;
grant all on "better_supabase"."stock_lots" to service_role;
drop policy if exists stock_lots_read on "better_supabase"."stock_lots";
create policy stock_lots_read on "better_supabase"."stock_lots"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_serials" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "serial" text not null check (length("serial") between 1 and 100),
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."inventory_locations" ("id") on delete set null,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete set null,
  "status" text not null default 'in_stock' check ("status" in ('in_stock', 'out', 'scrapped')),
  "movement_id" uuid,
  "updated_at" timestamptz not null default now(),
  unique ("variant_id", "serial")
);
create index if not exists stock_serials_location_id_idx on "better_supabase"."stock_serials" ("location_id");
create index if not exists stock_serials_bin_idx on "better_supabase"."stock_serials" ("bin_id");
create index if not exists stock_serials_lot_idx on "better_supabase"."stock_serials" ("lot_id");
create index if not exists stock_serials_movement_idx on "better_supabase"."stock_serials" ("movement_id");
create index if not exists stock_serials_tenant_idx on "better_supabase"."stock_serials" ("org_id");
alter table "better_supabase"."stock_serials" enable row level security;
revoke all on "better_supabase"."stock_serials" from public, anon, authenticated;
grant select on "better_supabase"."stock_serials" to authenticated;
grant all on "better_supabase"."stock_serials" to service_role;
drop policy if exists stock_serials_read on "better_supabase"."stock_serials";
create policy stock_serials_read on "better_supabase"."stock_serials"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_buckets" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid references "better_supabase"."stock_bins" ("id") on delete restrict,
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict,
  "on_hand" numeric(20, 6) not null default 0,
  "updated_at" timestamptz not null default now(),
  check ("bin_id" is not null or "lot_id" is not null),
  unique nulls not distinct ("variant_id", "location_id", "bin_id", "lot_id")
);
create index if not exists stock_buckets_location_idx on "better_supabase"."stock_buckets" ("location_id");
create index if not exists stock_buckets_bin_idx on "better_supabase"."stock_buckets" ("bin_id");
create index if not exists stock_buckets_lot_idx on "better_supabase"."stock_buckets" ("lot_id");
create index if not exists stock_buckets_tenant_idx on "better_supabase"."stock_buckets" ("org_id");
alter table "better_supabase"."stock_buckets" enable row level security;
revoke all on "better_supabase"."stock_buckets" from public, anon, authenticated;
grant select on "better_supabase"."stock_buckets" to authenticated;
grant all on "better_supabase"."stock_buckets" to service_role;
drop policy if exists stock_buckets_read on "better_supabase"."stock_buckets";
create policy stock_buckets_read on "better_supabase"."stock_buckets"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

create table if not exists "better_supabase"."stock_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "line_id" text,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "allocated" numeric(20, 6) not null default 0 check ("allocated" >= 0),
  "fulfilled" numeric(20, 6) not null default 0 check ("fulfilled" >= 0),
  "backordered" numeric(20, 6) generated always as (case when "status" = 'open' then "quantity" - "allocated" - "fulfilled" else 0 end) stored,
  "status" text not null default 'open' check ("status" in ('open', 'fulfilled', 'released')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("allocated" + "fulfilled" <= "quantity")
);
create index if not exists stock_allocations_document_idx on "better_supabase"."stock_allocations" ("org_id", "document_type", "document_id");
create index if not exists stock_allocations_open_idx on "better_supabase"."stock_allocations" ("variant_id", "location_id", "created_at") where "status" = 'open';
create index if not exists stock_allocations_location_idx on "better_supabase"."stock_allocations" ("location_id");
create index if not exists stock_allocations_variant_idx on "better_supabase"."stock_allocations" ("variant_id");
alter table "better_supabase"."stock_allocations" enable row level security;
revoke all on "better_supabase"."stock_allocations" from public, anon, authenticated;
grant select on "better_supabase"."stock_allocations" to authenticated;
grant all on "better_supabase"."stock_allocations" to service_role;
drop policy if exists stock_allocations_read on "better_supabase"."stock_allocations";
create policy stock_allocations_read on "better_supabase"."stock_allocations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')));

drop function if exists "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text);

-- Posts a stock movement to the ledger and applies it to its level and
-- buckets. detail is null or an object with binId, lotId or lot ({ code,
-- expiresOn }), serials (an array, one per unit of a serial-tracked
-- variant), and unitCost and currency for a receipt under average costing.
-- Without a bin or lot, stock leaves first-expiry-first-out: the lot that
-- expires first, then the stock outside any lot; a sale or a transfer out
-- skips hold bins and expired lots. A tracked variant without backorders
-- can't go below zero on hand in any bucket, and a sale or a transfer out
-- can't take available below zero. Returns the ledger transaction, the
-- movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, reason text, reference_type text default null, reference_id text default null, note text default null, detail jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason = 'receipt' then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason = 'receipt'
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("org_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("org_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("org_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    null;
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, numeric, text, text, text, text, jsonb) from public, anon, authenticated;

-- Sets how a variant's stock is counted: its unit and decimal scale, lot or
-- serial tracking, expiry dates and weighted average costing. Null keeps a
-- setting. The unit, scale, tracking and costing are fixed once the variant
-- has stock history. Returns the item.
create or replace function "better_supabase"."set_stock_item"(variant uuid, unit text, scale smallint, tracking text, tracks_expiry boolean, costing text, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."stock_items"%rowtype;
  v_old "better_supabase"."stock_items"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select cv."org_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = set_stock_item.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select * into v_old from "better_supabase"."stock_items" x where x."variant_id" = set_stock_item.variant for update;
  v_row."variant_id" := set_stock_item.variant;
  v_row."org_id" := v_tenant;
  v_row."unit" := coalesce(set_stock_item.unit, v_old."unit", 'item');
  v_row."scale" := coalesce(set_stock_item.scale, v_old."scale", 0);
  v_row."tracking" := coalesce(set_stock_item.tracking, v_old."tracking", 'none');
  v_row."tracks_expiry" := coalesce(set_stock_item.tracks_expiry, v_old."tracks_expiry", false);
  v_row."costing" := coalesce(set_stock_item.costing, v_old."costing", 'none');
  v_row."currency" := coalesce(upper(set_stock_item.currency), v_old."currency");
  v_row."average_cost" := v_old."average_cost";
  if v_row."unit" !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'the unit must be 1 to 32 lowercase letters, digits or underscores' using errcode = '22023', hint = 'INVENTORY_UNIT_INVALID';
  end if;
  if v_row."scale" not between 0 and 6 then
    raise exception 'the scale must be 0 to 6 decimals' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."tracking" not in ('none', 'lot', 'serial') then
    raise exception 'tracking must be one of none, lot, serial' using errcode = '22023', hint = 'INVENTORY_TRACKING_INVALID';
  end if;
  if v_row."tracking" = 'serial' and v_row."scale" <> 0 then
    raise exception 'serial tracking counts whole units, so the scale must be 0' using errcode = '22023', hint = 'INVENTORY_SCALE_INVALID';
  end if;
  if v_row."costing" not in ('none', 'average') then
    raise exception 'costing must be one of none, average' using errcode = '22023', hint = 'INVENTORY_COSTING_INVALID';
  end if;
  if v_row."costing" <> 'none' and (v_row."currency" is null or "better_supabase"."currency_minor_units"(v_row."currency") is null) then
    raise exception 'average costing needs an ISO 4217 currency' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if (v_row."unit", v_row."scale", v_row."tracking", v_row."costing", v_row."currency")
      is distinct from (coalesce(v_old."unit", 'item'), coalesce(v_old."scale", 0), coalesce(v_old."tracking", 'none'),
        coalesce(v_old."costing", 'none'), v_old."currency")
    and exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = set_stock_item.variant) then
    raise exception 'the variant has stock history; its unit, scale, tracking and costing are fixed' using errcode = '55000', hint = 'INVENTORY_ITEM_LOCKED';
  end if;
  v_row."updated_at" := now();
  insert into "better_supabase"."stock_items" as x select v_row.*
  on conflict ("variant_id") do update set "unit" = excluded."unit", "scale" = excluded."scale",
    "tracking" = excluded."tracking", "tracks_expiry" = excluded."tracks_expiry", "costing" = excluded."costing",
    "currency" = excluded."currency", "updated_at" = now();
  return jsonb_build_object('variantId', v_row."variant_id", 'unit', v_row."unit", 'scale', v_row."scale",
    'tracking', v_row."tracking", 'tracksExpiry', v_row."tracks_expiry", 'costing', v_row."costing",
    'currency', v_row."currency", 'averageCost', v_row."average_cost"::text);
end;
$$;
revoke execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) from public, anon;
grant execute on function "better_supabase"."set_stock_item"(uuid, text, smallint, text, boolean, text, text) to authenticated, service_role;

-- Creates a bin at a location (bin null) or updates one. Stock in a hold bin
-- counts as held: on hand, but not available to sell.
create or replace function "better_supabase"."save_bin"(location uuid, bin uuid, code text, name text, hold boolean, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_id uuid := save_bin.bin;
  v_hold boolean;
  v_was boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = save_bin.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_bin.code is null or save_bin.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_BIN_CODE_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."stock_bins" ("org_id", "location_id", "code", "name", "hold", "active")
      values (v_tenant, save_bin.location, save_bin.code, save_bin.name, coalesce(save_bin.hold, false), coalesce(save_bin.active, true))
      returning "id", "hold" into v_id, v_hold;
      v_was := v_hold;
    else
      select x."hold" into v_was from "better_supabase"."stock_bins" x where x."id" = v_id and x."location_id" = save_bin.location for update;
      if not found then
        raise exception 'bin not found at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
      end if;
      update "better_supabase"."stock_bins" x set "code" = save_bin.code, "name" = save_bin.name,
        "hold" = coalesce(save_bin.hold, x."hold"), "active" = coalesce(save_bin.active, x."active")
      where x."id" = v_id
      returning x."hold" into v_hold;
    end if;
  exception when unique_violation then
    raise exception 'another bin at this location has this code' using errcode = '23505', hint = 'INVENTORY_BIN_CODE_TAKEN';
  end;
  if v_hold <> v_was then
    update "better_supabase"."stock_levels" x set "held" = greatest(x."held" + case when v_hold then y.on_hand else -y.on_hand end, 0), "updated_at" = now()
    from (select z."variant_id" as variant, sum(z."on_hand") as on_hand from "better_supabase"."stock_buckets" z
      where z."bin_id" = v_id and z."on_hand" > 0 group by z."variant_id") y
    where x."variant_id" = y.variant and x."location_id" = save_bin.location;
  end if;
  return jsonb_build_object('id', v_id, 'code', save_bin.code, 'hold', v_hold, 'active', coalesce(save_bin.active, true));
end;
$$;
revoke execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."save_bin"(uuid, uuid, text, text, boolean, boolean) to authenticated, service_role;

-- The lot of a variant with this code, created when missing. A given
-- expires_on replaces the stored one.
create or replace function "better_supabase"."stock_lot_for"(tenant uuid, variant uuid, code text, expires_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if stock_lot_for.code is null or length(stock_lot_for.code) not between 1 and 100 then
    raise exception 'a lot code is 1 to 100 characters' using errcode = '22023', hint = 'INVENTORY_LOT_INVALID';
  end if;
  insert into "better_supabase"."stock_lots" as x ("org_id", "variant_id", "code", "expires_on")
  values (stock_lot_for.tenant, stock_lot_for.variant, stock_lot_for.code, stock_lot_for.expires_on)
  on conflict ("variant_id", "code") do update
    set "expires_on" = coalesce(excluded."expires_on", x."expires_on")
  returning x."id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."stock_lot_for"(uuid, uuid, text, date) from public, anon, authenticated;

-- Creates a lot of a variant or updates its expiry date. Returns the lot.
create or replace function "better_supabase"."save_lot"(variant uuid, code text, expires_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  select cv."org_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = save_lot.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  v_id := "better_supabase"."stock_lot_for"(v_tenant, save_lot.variant, save_lot.code, save_lot.expires_on);
  return (select jsonb_build_object('id', x."id", 'code', x."code", 'expiresOn', x."expires_on")
    from "better_supabase"."stock_lots" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_lot"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."save_lot"(uuid, text, date) to authenticated, service_role;

-- A variant's stock at a location: the level, each bin and lot bucket, the
-- stock outside any bin or lot, and the serial numbers in stock there.
create or replace function "better_supabase"."stock_detail"(variant uuid, location uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_level record;
  v_buckets jsonb;
  v_bucketed numeric;
begin
  select x."org_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = stock_detail.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  select x."on_hand" as on_hand, x."reserved" as reserved, x."held" as held, x."available" as available
  into v_level from "better_supabase"."stock_levels" x where x."variant_id" = stock_detail.variant and x."location_id" = stock_detail.location;
  select coalesce(jsonb_agg(jsonb_build_object('binId', y."bin_id", 'binCode', bn."code", 'hold', coalesce(bn."hold", false),
      'lotId', y."lot_id", 'lotCode', lo."code", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on" nulls last, bn."code" nulls first, lo."code"), '[]'::jsonb),
    coalesce(sum(y."on_hand"), 0)
  into v_buckets, v_bucketed
  from "better_supabase"."stock_buckets" y
  left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
  left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
  where y."variant_id" = stock_detail.variant and y."location_id" = stock_detail.location and y."on_hand" <> 0;
  return jsonb_build_object('variantId', stock_detail.variant, 'locationId', stock_detail.location,
    'onHand', coalesce(v_level.on_hand, 0)::text, 'reserved', coalesce(v_level.reserved, 0)::text,
    'held', coalesce(v_level.held, 0)::text, 'available', coalesce(v_level.available, 0)::text,
    'unbinned', (coalesce(v_level.on_hand, 0) - v_bucketed)::text, 'buckets', v_buckets,
    'serials', coalesce((select jsonb_agg(z."serial" order by z."serial") from "better_supabase"."stock_serials" z
      where z."variant_id" = stock_detail.variant and z."location_id" = stock_detail.location and z."status" = 'in_stock'), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."stock_detail"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stock_detail"(uuid, uuid) to authenticated, service_role;

-- The lots with stock that expire on or before a date, soonest first.
create or replace function "better_supabase"."expiring_lots"(tenant uuid, before date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expiring_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lotId', lo."id", 'code', lo."code", 'variantId', lo."variant_id",
      'locationId', y."location_id", 'binId', y."bin_id", 'expiresOn', lo."expires_on", 'onHand', y."on_hand"::text)
      order by lo."expires_on", lo."code", y."location_id")
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."org_id" = expiring_lots.tenant and y."on_hand" > 0
      and lo."expires_on" <= coalesce(expiring_lots.before, current_date)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."expiring_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expiring_lots"(uuid, date) to authenticated, service_role;

-- Writes off the stock of every lot that expired before as_of (today by
-- default) with an expired movement. Returns how many buckets it emptied.
create or replace function "better_supabase"."expire_lots"(tenant uuid, as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', expire_lots.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select y."variant_id" as variant, y."location_id" as location, y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand,
      (select array_agg(z."serial") from "better_supabase"."stock_serials" z where z."variant_id" = y."variant_id" and z."lot_id" = y."lot_id"
        and z."location_id" = y."location_id" and z."bin_id" is not distinct from y."bin_id" and z."status" = 'in_stock') as serials
    from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
    where y."org_id" = expire_lots.tenant and y."on_hand" > 0 and lo."expires_on" < coalesce(expire_lots.as_of, current_date)
    order by lo."expires_on"
    for update of y
  loop
    perform "better_supabase"."move_stock"(expire_lots.tenant, v_row.variant, v_row.location, -v_row.on_hand, 'expired', 'stock_lot', v_row.lot::text, null, jsonb_strip_nulls(jsonb_build_object('binId', v_row.bin, 'lotId', v_row.lot, 'serials', to_jsonb(v_row.serials))));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_lots"(uuid, date) from public, anon;
grant execute on function "better_supabase"."expire_lots"(uuid, date) to authenticated, service_role;

-- A variant's weighted average cost, its stock across locations and the value
-- of that stock in minor units of the cost currency.
create or replace function "better_supabase"."stock_valuation"(variant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_item record;
begin
  select cv."org_id" into v_tenant from "better_supabase"."product_variants" cv where cv."id" = stock_valuation.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  select x."costing" as costing, x."currency" as currency, x."average_cost" as average_cost
  into v_item from "better_supabase"."stock_items" x where x."variant_id" = stock_valuation.variant;
  return jsonb_build_object('variantId', stock_valuation.variant, 'costing', coalesce(v_item.costing, 'none'),
    'currency', v_item.currency, 'averageCost', v_item.average_cost::text,
    'onHand', (select coalesce(sum(x."on_hand"), 0) from "better_supabase"."stock_levels" x where x."variant_id" = stock_valuation.variant)::text,
    'value', coalesce((select y."balance" from "better_supabase"."ledger_accounts" a join "better_supabase"."ledger_balances" y on y."account_id" = a."id"
      where a."org_id" = v_tenant and a."code" = 'stock_value:' || stock_valuation.variant::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."stock_valuation"(uuid) from public, anon;
grant execute on function "better_supabase"."stock_valuation"(uuid) to authenticated, service_role;

-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function "better_supabase"."fill_backorders"(tenant uuid, variant uuid, location uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_available numeric;
  v_take numeric;
  v_total numeric := 0;
begin
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."backordered" as quantity
    from "better_supabase"."stock_allocations" x
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location
      and x."status" = 'open' and x."backordered" > 0
    order by x."created_at", x."id"
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" + v_take, "updated_at" = now() where x."id" = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    null;
  end loop;
  if v_total > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_total, 0), "updated_at" = now()
    where x."variant_id" = fill_backorders.variant and x."location_id" = fill_backorders.location;
  end if;
  return v_total;
end;
$$;
revoke execute on function "better_supabase"."fill_backorders"(uuid, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function "better_supabase"."allocate_stock"(tenant uuid, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_location uuid := allocate_stock.location;
  v_available numeric;
  v_take numeric;
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', allocate_stock.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."org_id" = allocate_stock.tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    raise exception 'an allocation names its document type and id' using errcode = '22023', hint = 'INVENTORY_DOCUMENT_INVALID';
  end if;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    left join "better_supabase"."stock_levels" s on s."location_id" = y."id" and s."variant_id" = allocate_stock.variant
    where y."org_id" = allocate_stock.tenant and y."active"
    order by coalesce(s."available", 0) desc, y."code"
    limit 1;
    if v_location is null then
      raise exception 'the organization has no active location' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
    end if;
  elsif not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location and y."org_id" = allocate_stock.tenant and y."active") then
    raise exception 'location not found or inactive' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_levels" ("org_id", "variant_id", "location_id")
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict ("variant_id", "location_id") do nothing;
  select x."available" into v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = allocate_stock.variant and x."location_id" = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = allocate_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_allocations" as x ("org_id", "variant_id", "location_id", "document_type", "document_id", "line_id", "quantity", "allocated")
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity
  into v_row;
  if v_take > 0 then
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + v_take, 0), "updated_at" = now()
    where x."variant_id" = allocate_stock.variant and x."location_id" = v_location;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."allocate_stock"(uuid, uuid, uuid, numeric, text, text, text, boolean) to authenticated, service_role;

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function "better_supabase"."fulfill_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_from_held numeric;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = fulfill_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'open' then
    raise exception 'the allocation is no longer open' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what the allocation has left' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_from_held, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_allocations" x set "allocated" = x."allocated" - v_from_held,
    "fulfilled" = x."fulfilled" + fulfill_allocation.quantity,
    "status" = case when x."fulfilled" + fulfill_allocation.quantity >= x."quantity" then 'fulfilled' else 'open' end,
    "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -fulfill_allocation.quantity, 'sale', v_row.document_type, v_row.document_id, null, fulfill_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."fulfill_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function "better_supabase"."restore_allocation"(allocation uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity,
    x."allocated" as allocated, x."fulfilled" as fulfilled, x."status" as status
  into v_row from "better_supabase"."stock_allocations" x where x."id" = restore_allocation.allocation for update;
  if not found then
    raise exception 'allocation not found' using errcode = 'P0002', hint = 'INVENTORY_ALLOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status = 'released' then
    raise exception 'the allocation was released' using errcode = '55000', hint = 'INVENTORY_ALLOCATION_CLOSED';
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    raise exception 'the quantity must be more than zero and at most what was fulfilled' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  update "better_supabase"."stock_allocations" x set "fulfilled" = x."fulfilled" - restore_allocation.quantity, "status" = 'open', "updated_at" = now()
  where x."id" = v_row.id;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, restore_allocation.quantity, 'return', v_row.document_type, v_row.document_id, null, restore_allocation.detail);
  return (select jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") || jsonb_build_object('movementId', v_movement) from "better_supabase"."stock_allocations" x where x."id" = v_row.id);
end;
$$;
revoke execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."restore_allocation"(uuid, numeric, jsonb) to authenticated, service_role;

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function "better_supabase"."release_allocations"(tenant uuid, document_type text, document_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', release_allocations.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  for v_row in
    select x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
      x."document_type" as document_type, x."document_id" as document_id, x."quantity" as quantity, x."allocated" as allocated
    from "better_supabase"."stock_allocations" x
    where x."org_id" = release_allocations.tenant and x."document_type" = release_allocations.document_type
      and x."document_id" = release_allocations.document_id and x."status" = 'open'
    order by x."created_at"
    for update
  loop
    if v_row.allocated > 0 then
      update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" + -v_row.allocated, 0), "updated_at" = now()
    where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    end if;
    update "better_supabase"."stock_allocations" x set "allocated" = 0, "status" = 'released', "updated_at" = now() where x."id" = v_row.id;
    null;
    if v_row.allocated > 0 then
      perform "better_supabase"."fill_backorders"(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."release_allocations"(uuid, text, text) to authenticated, service_role;

-- A document's allocations, oldest first.
create or replace function "better_supabase"."list_allocations"(tenant uuid, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_allocations.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'variantId', x."variant_id", 'locationId', x."location_id",
    'documentType', x."document_type", 'documentId', x."document_id", 'lineId', x."line_id",
    'quantity', x."quantity"::text, 'allocated', x."allocated"::text, 'fulfilled', x."fulfilled"::text,
    'backordered', x."backordered"::text, 'status', x."status", 'createdAt', x."created_at") order by x."created_at", x."id")
    from "better_supabase"."stock_allocations" x where x."org_id" = list_allocations.tenant
      and x."document_type" = list_allocations.document_type and x."document_id" = list_allocations.document_id), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_allocations"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_allocations"(uuid, text, text) to authenticated, service_role;

-- Creates a location (location null) or updates one, with the extra columns
-- in fields by name. Returns its id, code and active flag.
drop function if exists "better_supabase"."save_location"(uuid, uuid, text, text, text);
create or replace function "better_supabase"."save_location"(tenant uuid, location uuid, code text, name text, kind text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("org_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."org_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_location"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Turns a location on or off. Reservations need an active location.
create or replace function "better_supabase"."set_location_active"(location uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_location_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_location_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a location without stock history. Deactivate one that has some.
create or replace function "better_supabase"."delete_location"(location uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."org_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_location"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_location"(uuid) to authenticated, service_role;

-- Adds or removes stock at a location through the ledger. detail names the
-- bin, lot, serial numbers or unit cost, as for move_stock. Returns the
-- movement id and the level's on-hand and available quantities.
drop function if exists "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text);
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity numeric, reason text, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand numeric;
  v_available numeric;
begin
  select x."org_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."org_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'scrap') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt, scrap' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, numeric, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note, adjust_stock.detail);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$$;
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, numeric, text, text, jsonb) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
-- With a binId or lotId in detail it counts that bin or lot only; without,
-- the stock outside any bin or lot.
drop function if exists "better_supabase"."count_stock"(uuid, uuid, integer, text);
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted numeric, note text, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta numeric;
  v_available numeric;
  v_bin uuid := nullif(count_stock.detail ->> 'binId', '')::uuid;
  v_lot uuid := nullif(count_stock.detail ->> 'lotId', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."org_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("org_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  if v_bin is null and v_lot is null then
    select count_stock.counted - x."on_hand" + coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location), 0)
    into v_delta from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  else
    v_delta := count_stock.counted - coalesce((select y."on_hand" from "better_supabase"."stock_buckets" y
      where y."variant_id" = count_stock.variant and y."location_id" = count_stock.location
        and y."bin_id" is not distinct from v_bin and y."lot_id" is not distinct from v_lot), 0);
  end if;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note, jsonb_strip_nulls(jsonb_build_object('binId', v_bin, 'lotId', v_lot, 'serials', count_stock.detail -> 'serials')));
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, numeric, text, jsonb) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
drop function if exists "better_supabase"."set_reorder_point"(uuid, uuid, integer);
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."org_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("org_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, numeric) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
drop function if exists "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz);
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity numeric, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before numeric;
  v_after numeric;
  v_point numeric;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."org_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, numeric, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("org_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0) from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("org_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$$;
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, numeric, text, text, timestamptz) to authenticated, service_role;

-- Turns an active reservation into a sale: the ledger takes the stock out.
create or replace function "better_supabase"."commit_reservation"(reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null, null);
  null;
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
end;
$$;
revoke execute on function "better_supabase"."commit_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."commit_reservation"(uuid) to authenticated, service_role;

-- Gives an active reservation's stock back. False when it isn't active.
create or replace function "better_supabase"."release_reservation"(reservation uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."org_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status
  into v_row from "better_supabase"."stock_reservations" x where x."id" = release_reservation.reservation for update;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    return false;
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'released', "updated_at" = now()
  where x."id" = release_reservation.reservation;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."release_reservation"(uuid) from public, anon;
grant execute on function "better_supabase"."release_reservation"(uuid) to authenticated, service_role;

-- Releases active reservations past their expiry, oldest first, up to
-- max_rows. Service only; run it on a schedule. Returns how many it released.
create or replace function "better_supabase"."expire_reservations"(max_rows integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x."id" as id, x."org_id" as tenant, x."variant_id" as variant,
      x."location_id" as location, x."quantity" as quantity
    from "better_supabase"."stock_reservations" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit greatest(coalesce(expire_reservations.max_rows, 500), 1)
    for update skip locked
  loop
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row.id;
    update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_reservations"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_reservations"(integer) to service_role;

-- Drafts a transfer of stock between two locations of one organization.
-- lines: [{ "variantId": uuid, "quantity": n, "detail"?: { binId, lotId,
-- serials } }]; detail picks the stock to take, as for move_stock.
create or replace function "better_supabase"."create_transfer"(tenant uuid, from_location uuid, to_location uuid, lines jsonb, note text)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."org_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."org_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("org_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("org_id", "transfer_id", "variant_id", "quantity", "detail")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric,
    case when jsonb_typeof(e -> 'detail') = 'object' then e -> 'detail' end
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."create_transfer"(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- Takes a draft transfer's stock out of its source location.
create or replace function "better_supabase"."ship_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer
  loop
    v_movement := "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, -v_line.quantity, 'transfer_out', 'transfer', ship_transfer.transfer::text, null, v_line.detail);
    update "better_supabase"."stock_transfer_lines" x set "detail" = jsonb_strip_nulls(jsonb_build_object('serials', v_line.detail -> 'serials',
      'parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."transfer_id" = ship_transfer.transfer and x."variant_id" = v_line.variant;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."ship_transfer"(uuid) to authenticated, service_role;

-- Puts an in-transit transfer's stock into its destination.
create or replace function "better_supabase"."receive_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.to_location, v_part.quantity, 'transfer_in', 'transfer', receive_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."receive_transfer"(uuid) to authenticated, service_role;

-- Cancels a draft or in-transit transfer; in-transit stock goes back to the source.
create or replace function "better_supabase"."cancel_transfer"(transfer uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_part record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    for v_line in
    select x."variant_id" as variant, x."quantity" as quantity, x."detail" as detail
    from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer
  loop
    for v_part in
      select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
      from jsonb_array_elements(coalesce(v_line.detail -> 'parts', jsonb_build_array(jsonb_build_object('quantity', v_line.quantity)))) p
    loop
      perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.from_location, v_part.quantity, 'transfer_in', 'transfer', cancel_transfer.transfer::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_part.lot, 'serials', (select jsonb_agg(z."serial") from "better_supabase"."stock_serials" z
          where z."variant_id" = v_line.variant and z."serial" in (select jsonb_array_elements_text(v_line.detail -> 'serials'))
            and z."lot_id" is not distinct from v_part.lot))));
    end loop;
  end loop;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_transfer"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_transfer"(uuid) to authenticated, service_role;

-- Creates a draft purchase order (purchase_order null) or replaces a draft's
-- fields and lines. lines: [{ "variantId": uuid, "quantity": n, "unitCost": "minor units" }].
-- supplier_type and supplier_id name a config.subjects record, or are both null.
create or replace function "better_supabase"."save_purchase_order"(tenant uuid, purchase_order uuid, location uuid, supplier_type text, supplier_id text, currency text, expected_at timestamptz, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."org_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."org_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("org_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."org_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("org_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$$;
revoke execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) from public, anon;
grant execute on function "better_supabase"."save_purchase_order"(uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text) to authenticated, service_role;

-- Sends a draft purchase order: its quantities count as incoming at its location.
create or replace function "better_supabase"."place_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = place_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  insert into "better_supabase"."stock_levels" as x ("org_id", "variant_id", "location_id", "incoming")
  select v_row.tenant, y."variant_id", v_row.location, y."quantity_ordered"
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = place_purchase_order.purchase_order
  on conflict ("variant_id", "location_id") do update
    set "incoming" = x."incoming" + excluded."incoming", "updated_at" = now();
  update "better_supabase"."purchase_orders" x set "status" = 'ordered', "placed_at" = now(), "updated_at" = now()
  where x."id" = place_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."place_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."place_purchase_order"(uuid) to authenticated, service_role;

-- Receives some or all of a placed order's lines into stock.
-- lines: [{ "lineId": uuid, "quantity": n, "lot"?: { code, expiresOn },
-- "lotId"?, "binId"?, "serials"? }]; the line's unit cost feeds the
-- variant's weighted average cost. Lines left short stay on
-- backorder until a later receipt or a cancel. Returns the new status and
-- the quantity still on backorder.
create or replace function "better_supabase"."receive_purchase_order"(purchase_order uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_line record;
  v_backordered numeric;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or case when coalesce(e ->> 'quantity', '') ~ '^[0-9]{1,14}([.][0-9]{1,6})?$' then (e ->> 'quantity')::numeric <= 0 else true end
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::numeric as quantity, y."unit_cost" as unit_cost,
      jsonb_strip_nulls(jsonb_build_object('lot', e -> 'lot', 'lotId', e -> 'lotId', 'binId', e -> 'binId', 'serials', e -> 'serials')) as detail
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null, v_line.detail || jsonb_build_object('unitCost', v_line.unit_cost::text, 'currency', v_row.currency::text));
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  null;
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$$;
revoke execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."receive_purchase_order"(uuid, jsonb) to authenticated, service_role;

-- Cancels a purchase order that isn't fully received; what's still on
-- backorder stops counting as incoming.
create or replace function "better_supabase"."cancel_purchase_order"(purchase_order uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id, x."currency" as currency
  into v_row from "better_supabase"."purchase_orders" x where x."id" = cancel_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if v_row.status <> 'draft' then
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - (y."quantity_ordered" - y."quantity_received"), 0), "updated_at" = now()
    from "better_supabase"."purchase_order_lines" y
    where y."purchase_order_id" = cancel_purchase_order.purchase_order
      and x."variant_id" = y."variant_id" and x."location_id" = v_row.location;
  end if;
  update "better_supabase"."purchase_orders" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = cancel_purchase_order.purchase_order;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_purchase_order"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_purchase_order"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."inventory_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_select on "better_supabase"."inventory_locations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_items";
create policy bsb_tenant_scope_select on "better_supabase"."stock_items" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_items";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_items" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_items";
create policy bsb_tenant_scope_update on "better_supabase"."stock_items" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_items";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_items" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_bins";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_select on "better_supabase"."stock_bins" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_bins" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_update on "better_supabase"."stock_bins" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_bins";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_bins" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lots" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lots" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lots" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lots";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lots" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_serials";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_select on "better_supabase"."stock_serials" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_serials" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_update on "better_supabase"."stock_serials" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_serials";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_serials" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_buckets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_select on "better_supabase"."stock_buckets" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_buckets" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_update on "better_supabase"."stock_buckets" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_buckets";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_buckets" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_allocations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_allocations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_allocations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_allocations" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:eb0b55f4af25785eab88a0096693d8af6e7eb7ca85ed10ec217e2bad1b3938fc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
