-- ==== schema supabase/schemas/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block inventory@2 managed
-- @bsb-hash sha256:17bc269bdd90351a75ed82285d87038dc90a6b84a9a8b6ae99a203eb2961d634
-- Stock per catalog variant and location: movements posted to the ledger block, reservations with expiry, transfers and purchase orders with partial receiving.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Stock per catalog variant and location: movements posted to the ledger,
-- reservations with expiry, transfers and purchase orders with receiving.

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
  "on_hand" integer not null default 0,
  "reserved" integer not null default 0 check ("reserved" >= 0),
  "incoming" integer not null default 0 check ("incoming" >= 0),
  "available" integer generated always as ("on_hand" - "reserved") stored,
  "reorder_point" integer check ("reorder_point" >= 0),
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
  "quantity" integer not null check ("quantity" > 0),
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
  "quantity" integer not null check ("quantity" > 0),
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
  "quantity_ordered" integer not null check ("quantity_ordered" > 0),
  "quantity_received" integer not null default 0 check ("quantity_received" between 0 and "quantity_ordered"),
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

-- Posts a stock movement to the ledger and applies it to its level. A
-- tracked variant without backorders can't go below zero on hand, and a
-- sale or a transfer out can't take available (on hand minus reserved)
-- below zero. Returns the ledger transaction, the movement's id.
create or replace function "better_supabase"."move_stock"(tenant uuid, variant uuid, location uuid, quantity integer, reason text, reference_type text default null, reference_id text default null, note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_stock uuid;
  v_counter uuid;
  v_id uuid;
  v_on_hand integer;
  v_after integer;
  v_point integer;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  v_stock := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock', 'stock:' || move_stock.variant::text || ':' || move_stock.location::text,
    'Stock', 'item', 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
    jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location));
  v_counter := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter', case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end,
    case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, 'item', 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null);
  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason,
    jsonb_build_array(
      jsonb_build_object('account', v_stock, 'amount', move_stock.quantity),
      jsonb_build_object('account', v_counter, 'amount', -move_stock.quantity)),
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason));
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity)
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0
    and (v_on_hand < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')))
    and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  if v_point is not null and (v_after - move_stock.quantity) > v_point and v_after <= v_point then
    null;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text) from public, anon, authenticated;

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

-- Adds or removes stock at a location through the ledger. Returns the
-- movement id and the level's on-hand and available quantities.
create or replace function "better_supabase"."adjust_stock"(variant uuid, location uuid, quantity integer, reason text, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand integer;
  v_available integer;
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
    raise exception 'the quantity must be a non-zero whole number' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, integer, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::integer, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note);
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
revoke execute on function "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."adjust_stock"(uuid, uuid, integer, text, text) to authenticated, service_role;

-- Sets on-hand to a counted quantity, writing the difference to the ledger.
create or replace function "better_supabase"."count_stock"(variant uuid, location uuid, counted integer, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta integer;
  v_available integer;
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
  select count_stock.counted - x."on_hand" into v_delta from "better_supabase"."stock_levels" x
  where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note);
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    null;
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$$;
revoke execute on function "better_supabase"."count_stock"(uuid, uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."count_stock"(uuid, uuid, integer, text) to authenticated, service_role;

-- Sets the available quantity at or below which stock.reorder_point_reached fires.
create or replace function "better_supabase"."set_reorder_point"(variant uuid, location uuid, reorder_point integer)
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
revoke execute on function "better_supabase"."set_reorder_point"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."set_reorder_point"(uuid, uuid, integer) to authenticated, service_role;

-- Holds stock for a cart or an order until expires_at (15 minutes by default).
-- Releases the level's expired reservations first. Returns the reservation id,
-- its expiry and the level's available quantity.
create or replace function "better_supabase"."reserve_stock"(variant uuid, location uuid, quantity integer, reference_type text, reference_id text, expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before integer;
  v_after integer;
  v_point integer;
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
    raise exception 'the quantity must be a positive whole number' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, integer, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::integer, $4::text, $5::text)', v_hook::oid::regproc)
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
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0)::integer from expired e), 0)
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
revoke execute on function "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."reserve_stock"(uuid, uuid, integer, text, text, timestamptz) to authenticated, service_role;

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
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null);
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
-- lines: [{ "variantId": uuid, "quantity": n }].
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
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
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
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer
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
  perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.from_location, -x."quantity", 'transfer_out', 'transfer', ship_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer;
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
  perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.to_location, x."quantity", 'transfer_in', 'transfer', receive_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer;
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
    perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.from_location, x."quantity", 'transfer_in', 'transfer', cancel_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer;
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
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
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
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer, (e ->> 'unitCost')::bigint
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
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id
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
-- lines: [{ "lineId": uuid, "quantity": n }]. Lines left short stay on
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
  v_backordered bigint;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id
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
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::integer as quantity
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
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null);
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
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id
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
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
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
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."inventory_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_update on "better_supabase"."inventory_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."inventory_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."inventory_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_select on "better_supabase"."stock_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_update on "better_supabase"."stock_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_reservations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_select on "better_supabase"."stock_reservations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_reservations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_update on "better_supabase"."stock_reservations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_reservations";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_reservations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfers";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_transfer_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_select on "better_supabase"."stock_transfer_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_transfer_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_update on "better_supabase"."stock_transfer_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_transfer_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."purchase_order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."purchase_order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('inventory.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."purchase_order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."purchase_order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."purchase_order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_081_inventory.sql
-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:7af4bf38242915c1ac1ca3466776dabb15de68972ea047bd4e4f188446cab87f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
