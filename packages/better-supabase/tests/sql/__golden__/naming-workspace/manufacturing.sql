-- ==== schema supabase/schemas/900_better_supabase_154_manufacturing.sql
-- better-supabase module: manufacturing
-- @bsb-block manufacturing@1 managed
-- @bsb-hash sha256:d5be38d17d5b8bff19a3fc79a9f82566bc7b9292472a3170b116ac2b84bf2028
-- Versioned bills of materials with routings on work centers, production orders numbered MO-2026-0001 that allocate and consume components and receive the output at component plus work center cost through inventory, lot genealogy and recall, and material requirements that suggest purchase and production orders.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."boms";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."boms";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."boms";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."boms";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."boms";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."work_centers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_centers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_centers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_centers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_centers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bom_operations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bom_operations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bom_operations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bom_operations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bom_operations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bom_components";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bom_components";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bom_components";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bom_components";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bom_components";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."production_orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."production_order_operations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_order_operations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_order_operations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_order_operations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_order_operations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."production_consumptions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_consumptions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_consumptions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_consumptions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_consumptions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lot_links";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lot_links";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lot_links";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lot_links";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lot_links";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Manufacturing per organization: versioned bills of materials, work centers,
-- production orders that take components and receive output through the
-- inventory block's stock movements, and lot genealogy.

create table if not exists "better_supabase"."work_centers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  -- The machine or line, an asset of the assets block.
  "asset_id" uuid,
  "hours_per_day" numeric(5, 2) not null default 8 check ("hours_per_day" > 0 and "hours_per_day" <= 24),
  -- Minor units per hour of work, in currency.
  "cost_rate" bigint not null default 0 check ("cost_rate" >= 0),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("cost_rate" = 0 or "currency" is not null)
);
create index if not exists "work_centers_tenant_idx" on "better_supabase"."work_centers" ("tenant_id", "name");
create index if not exists "work_centers_asset_idx" on "better_supabase"."work_centers" ("asset_id") where "asset_id" is not null;
alter table "better_supabase"."work_centers" enable row level security;
revoke all on "better_supabase"."work_centers" from public, anon, authenticated;
grant select on "better_supabase"."work_centers" to authenticated;
grant all on "better_supabase"."work_centers" to service_role;
drop policy if exists work_centers_read on "better_supabase"."work_centers";
create policy work_centers_read on "better_supabase"."work_centers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."boms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The variant the bill of materials makes.
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete restrict,
  -- 1, 2, 3 per variant; a production order pins one version.
  "version" integer not null check ("version" > 0),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'archived')),
  -- How much of the variant one run of the components makes.
  "quantity" numeric(20, 6) not null default 1 check ("quantity" > 0),
  "note" text check ("note" is null or length("note") <= 10000),
  "activated_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  unique ("variant_id", "version")
);
-- One active version per variant.
create unique index if not exists "boms_active_key" on "better_supabase"."boms" ("variant_id") where "status" = 'active';
create index if not exists "boms_tenant_idx" on "better_supabase"."boms" ("tenant_id", "status");
alter table "better_supabase"."boms" enable row level security;
revoke all on "better_supabase"."boms" from public, anon, authenticated;
grant select on "better_supabase"."boms" to authenticated;
grant all on "better_supabase"."boms" to service_role;
drop policy if exists boms_read on "better_supabase"."boms";
create policy boms_read on "better_supabase"."boms"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."bom_operations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "bom_id" uuid not null,
  -- 10, 20, 30: the order operations run in.
  "sequence" integer not null check ("sequence" > 0),
  "work_center_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "setup_minutes" numeric(10, 2) not null default 0 check ("setup_minutes" >= 0),
  "run_minutes_per_unit" numeric(10, 4) not null default 0 check ("run_minutes_per_unit" >= 0),
  -- A drive node with the work instructions.
  "instructions_node_id" uuid,
  -- An inspection kind; starting the operation schedules one.
  "inspection_template" text check ("inspection_template" is null or length("inspection_template") between 1 and 63),
  unique ("bom_id", "sequence"),
  foreign key ("tenant_id", "bom_id") references "better_supabase"."boms" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "work_center_id") references "better_supabase"."work_centers" ("tenant_id", "id") on delete restrict
);
create index if not exists "bom_operations_parent_idx" on "better_supabase"."bom_operations" ("tenant_id", "bom_id", "sequence");
create index if not exists "bom_operations_center_idx" on "better_supabase"."bom_operations" ("tenant_id", "work_center_id");
create index if not exists "bom_operations_instructions_idx" on "better_supabase"."bom_operations" ("instructions_node_id") where "instructions_node_id" is not null;
alter table "better_supabase"."bom_operations" enable row level security;
revoke all on "better_supabase"."bom_operations" from public, anon, authenticated;
grant select on "better_supabase"."bom_operations" to authenticated;
grant all on "better_supabase"."bom_operations" to service_role;
drop policy if exists bom_operations_read on "better_supabase"."bom_operations";
create policy bom_operations_read on "better_supabase"."bom_operations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."bom_components" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "bom_id" uuid not null,
  "position" integer not null default 0,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete restrict,
  -- Per bom quantity of the made variant, in the component's unit.
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- Expected loss in basis points: 250 plans 2.5% more.
  "scrap_bps" integer not null default 0 check ("scrap_bps" between 0 and 10000),
  -- The operation that uses it, or null for the start of the run.
  "operation_id" uuid references "better_supabase"."bom_operations" ("id") on delete set null,
  foreign key ("tenant_id", "bom_id") references "better_supabase"."boms" ("tenant_id", "id") on delete cascade
);
create index if not exists "bom_components_parent_idx" on "better_supabase"."bom_components" ("tenant_id", "bom_id", "position");
create index if not exists "bom_components_variant_idx" on "better_supabase"."bom_components" ("variant_id");
create index if not exists "bom_components_operation_idx" on "better_supabase"."bom_components" ("operation_id") where "operation_id" is not null;
alter table "better_supabase"."bom_components" enable row level security;
revoke all on "better_supabase"."bom_components" from public, anon, authenticated;
grant select on "better_supabase"."bom_components" to authenticated;
grant all on "better_supabase"."bom_components" to service_role;
drop policy if exists bom_components_read on "better_supabase"."bom_components";
create policy bom_components_read on "better_supabase"."bom_components"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."production_orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- MO-2026-0001, from the numbering block when it numbers production orders.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete restrict,
  -- The bill of materials version the order was planned with.
  "bom_id" uuid not null,
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The inventory location the components come from and the output goes to.
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete restrict,
  "due_on" date,
  "status" text not null default 'draft' check ("status" in ('draft', 'released', 'in_progress', 'done', 'canceled')),
  "produced_quantity" numeric(20, 6) not null default 0 check ("produced_quantity" >= 0),
  "scrap_quantity" numeric(20, 6) not null default 0 check ("scrap_quantity" >= 0),
  "output_lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete set null,
  -- What completion valued the output at, in minor units of currency: the
  -- consumed components' stock value and the work centers' labor.
  "material_cost" bigint not null default 0,
  "labor_cost" bigint not null default 0 check ("labor_cost" >= 0),
  "currency" char(3),
  "note" text check ("note" is null or length("note") <= 10000),
  "released_at" timestamptz,
  "started_at" timestamptz,
  "completed_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "bom_id") references "better_supabase"."boms" ("tenant_id", "id") on delete restrict
);
create index if not exists "production_orders_tenant_idx" on "better_supabase"."production_orders" ("tenant_id", "status", "due_on");
create index if not exists "production_orders_version_idx" on "better_supabase"."production_orders" ("tenant_id", "bom_id");
create index if not exists "production_orders_variant_idx" on "better_supabase"."production_orders" ("variant_id", "status");
create index if not exists "production_orders_location_idx" on "better_supabase"."production_orders" ("location_id");
create index if not exists "production_orders_output_lot_idx" on "better_supabase"."production_orders" ("output_lot_id") where "output_lot_id" is not null;
alter table "better_supabase"."production_orders" enable row level security;
revoke all on "better_supabase"."production_orders" from public, anon, authenticated;
grant select on "better_supabase"."production_orders" to authenticated;
grant all on "better_supabase"."production_orders" to service_role;
drop policy if exists production_orders_read on "better_supabase"."production_orders";
create policy production_orders_read on "better_supabase"."production_orders"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."production_order_operations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "operation_id" uuid references "better_supabase"."bom_operations" ("id") on delete set null,
  "sequence" integer not null check ("sequence" > 0),
  "work_center_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  -- Setup plus run time for the order's quantity.
  "planned_minutes" numeric(12, 2) not null default 0 check ("planned_minutes" >= 0),
  "status" text not null default 'pending' check ("status" in ('pending', 'in_progress', 'done')),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "operator_id" uuid,
  -- The minutes worked, set when the operation finishes.
  "minutes" numeric(12, 2) check ("minutes" is null or "minutes" >= 0),
  -- The inspection its inspection template scheduled.
  "inspection_id" uuid,
  unique ("order_id", "sequence"),
  foreign key ("tenant_id", "order_id") references "better_supabase"."production_orders" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "work_center_id") references "better_supabase"."work_centers" ("tenant_id", "id") on delete restrict
);
create index if not exists "production_order_operations_parent_idx" on "better_supabase"."production_order_operations" ("tenant_id", "order_id", "sequence");
create index if not exists "production_order_operations_center_idx" on "better_supabase"."production_order_operations" ("tenant_id", "work_center_id", "status");
create index if not exists "production_order_operations_operation_idx" on "better_supabase"."production_order_operations" ("operation_id") where "operation_id" is not null;
create index if not exists "production_order_operations_inspection_idx" on "better_supabase"."production_order_operations" ("inspection_id") where "inspection_id" is not null;
alter table "better_supabase"."production_order_operations" enable row level security;
revoke all on "better_supabase"."production_order_operations" from public, anon, authenticated;
grant select on "better_supabase"."production_order_operations" to authenticated;
grant all on "better_supabase"."production_order_operations" to service_role;
drop policy if exists production_order_operations_read on "better_supabase"."production_order_operations";
create policy production_order_operations_read on "better_supabase"."production_order_operations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

create table if not exists "better_supabase"."production_consumptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete restrict,
  "lot_id" uuid references "better_supabase"."stock_lots" ("id") on delete restrict,
  "serial" text check ("serial" is null or length("serial") between 1 and 100),
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  -- The stock value it took, in minor units of currency; 0 without costing.
  "cost" bigint not null default 0,
  "currency" char(3),
  -- The stock movement, a ledger transaction.
  "movement_id" uuid not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  foreign key ("tenant_id", "order_id") references "better_supabase"."production_orders" ("tenant_id", "id") on delete cascade
);
create index if not exists "production_consumptions_parent_idx" on "better_supabase"."production_consumptions" ("tenant_id", "order_id", "created_at");
create index if not exists "production_consumptions_variant_idx" on "better_supabase"."production_consumptions" ("variant_id");
create index if not exists "production_consumptions_lot_idx" on "better_supabase"."production_consumptions" ("lot_id") where "lot_id" is not null;
create index if not exists "production_consumptions_movement_idx" on "better_supabase"."production_consumptions" ("movement_id");
alter table "better_supabase"."production_consumptions" enable row level security;
revoke all on "better_supabase"."production_consumptions" from public, anon, authenticated;
grant select on "better_supabase"."production_consumptions" to authenticated;
grant all on "better_supabase"."production_consumptions" to service_role;
drop policy if exists production_consumptions_read on "better_supabase"."production_consumptions";
create policy production_consumptions_read on "better_supabase"."production_consumptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));

-- Lot genealogy: the output lot of a production order (parent) and each lot
-- it consumed (child).
create table if not exists "better_supabase"."stock_lot_links" (
  "tenant_id" uuid not null,
  "parent_lot_id" uuid not null references "better_supabase"."stock_lots" ("id") on delete cascade,
  "child_lot_id" uuid not null references "better_supabase"."stock_lots" ("id") on delete cascade,
  "order_id" uuid not null,
  -- How much of the child lot went into the parent.
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "created_at" timestamptz not null default now(),
  primary key ("parent_lot_id", "child_lot_id", "order_id"),
  foreign key ("tenant_id", "order_id") references "better_supabase"."production_orders" ("tenant_id", "id") on delete cascade
);
create index if not exists "stock_lot_links_child_idx" on "better_supabase"."stock_lot_links" ("child_lot_id");
create index if not exists "stock_lot_links_order_idx" on "better_supabase"."stock_lot_links" ("tenant_id", "order_id");
alter table "better_supabase"."stock_lot_links" enable row level security;
revoke all on "better_supabase"."stock_lot_links" from public, anon, authenticated;
grant select on "better_supabase"."stock_lot_links" to authenticated;
grant all on "better_supabase"."stock_lot_links" to service_role;
drop policy if exists stock_lot_links_read on "better_supabase"."stock_lot_links";
create policy stock_lot_links_read on "better_supabase"."stock_lot_links"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')));


-- A quantity of a variant rounded up to the variant's stock scale, so planned
-- component quantities are quantities stock can move.
create or replace function "better_supabase"."production_quantity"(variant uuid, quantity numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(ceil(production_quantity.quantity * power(10::numeric, s.scale)) / power(10::numeric, s.scale), s.scale)
  from (select coalesce((select x."scale" from "better_supabase"."stock_items" x where x."variant_id" = production_quantity.variant), 0) as scale) s;
$$;
revoke execute on function "better_supabase"."production_quantity"(uuid, numeric) from public, anon, authenticated;

-- Whether the active bills of materials of variant reach target, at any level.
create or replace function "better_supabase"."bom_reaches"(variant uuid, target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive walk(variant, depth) as (
    select bom_reaches.variant, 0
    union
    select y."variant_id", walk.depth + 1
    from walk
    join "better_supabase"."boms" x on x."variant_id" = walk.variant and x."status" = 'active'
    join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where walk.depth < 20
  )
  select exists (select 1 from walk where walk.variant = bom_reaches.target and walk.depth > 0);
$$;
revoke execute on function "better_supabase"."bom_reaches"(uuid, uuid) from public, anon, authenticated;

-- Creates a draft version of a variant's bill of materials (bom_id null) or
-- replaces a draft's. input is { quantity, note, operations: [{ sequence,
-- workCenterId, title, setupMinutes, runMinutesPerUnit, instructionsNodeId,
-- inspectionTemplate }], components: [{ variantId, quantity, scrapBps,
-- operation }] }; a component's operation is the sequence of the operation
-- that uses it.
create or replace function "better_supabase"."save_bom"(tenant uuid, variant uuid, input jsonb, bom_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."boms";
  v_components jsonb;
  v_operations jsonb;
  v_quantity numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bom.tenant is not null and coalesce(better_supabase.can('tenant', save_bom.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to change bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bom.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = save_bom.variant and cv."tenant_id" = save_bom.tenant) then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  v_quantity := coalesce(nullif(save_bom.input ->> 'quantity', '')::numeric, 1);
  if v_quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  v_components := save_bom.input -> 'components';
  v_operations := coalesce(save_bom.input -> 'operations', '[]'::jsonb);
  if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) = 0 then
    raise exception 'a bill of materials lists at least one component' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if jsonb_typeof(v_operations) <> 'array' then
    raise exception 'operations must be an array' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e
    where jsonb_typeof(e) <> 'object' or nullif(e ->> 'variantId', '') is null
      or coalesce(nullif(e ->> 'quantity', '')::numeric, 0) <= 0
      or coalesce(nullif(e ->> 'scrapBps', '')::integer, 0) not between 0 and 10000) then
    raise exception 'each component names a variant, a quantity above zero and scrapBps from 0 to 10000' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where (e ->> 'variantId')::uuid = save_bom.variant) then
    raise exception 'a variant can''t be a component of itself' using errcode = '22023', hint = 'BOM_CYCLE';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_bom.tenant)) then
    raise exception 'a component isn''t a variant of this organization' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where jsonb_typeof(e) <> 'object' or coalesce(nullif(e ->> 'sequence', '')::integer, 0) <= 0
      or length(coalesce(trim(e ->> 'title'), '')) not between 1 and 200
      or coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0) < 0
      or coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0) < 0)
    or (select count(distinct e ->> 'sequence') from jsonb_array_elements(v_operations) e) <> jsonb_array_length(v_operations) then
    raise exception 'each operation has a unique sequence above zero, a title and minutes of zero or more' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where not exists (select 1 from "better_supabase"."work_centers" x where x."id" = nullif(e ->> 'workCenterId', '')::uuid
      and x."tenant_id" = save_bom.tenant and x."archived_at" is null)) then
    raise exception 'no such work center in this organization' using errcode = 'P0002', hint = 'WORK_CENTER_NOT_FOUND';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where nullif(e ->> 'operation', '') is not null
    and not exists (select 1 from jsonb_array_elements(v_operations) p where (p ->> 'sequence')::integer = (e ->> 'operation')::integer)) then
    raise exception 'a component names an operation sequence the bill of materials doesn''t have' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  
  

  if save_bom.bom_id is null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bom:' || save_bom.variant::text, 0));
    insert into "better_supabase"."boms" ("tenant_id", "variant_id", "version", "quantity", "note", "created_by")
    values (save_bom.tenant, save_bom.variant,
      coalesce((select max(x."version") from "better_supabase"."boms" x where x."variant_id" = save_bom.variant), 0) + 1,
      v_quantity, nullif(trim(save_bom.input ->> 'note'), ''), auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."boms" x where x."id" = save_bom.bom_id and x."tenant_id" = save_bom.tenant for update;
    if not found then
      raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'BOM_NOT_FOUND';
    end if;
    if v_row."variant_id" <> save_bom.variant or v_row."status" <> 'draft' then
      raise exception 'only a draft version of the same variant changes; save a new version instead' using errcode = '22023', hint = 'BOM_INVALID';
    end if;
    delete from "better_supabase"."bom_components" x where x."bom_id" = v_row."id";
    delete from "better_supabase"."bom_operations" x where x."bom_id" = v_row."id";
    update "better_supabase"."boms" x set "quantity" = v_quantity, "note" = nullif(trim(save_bom.input ->> 'note'), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;

  insert into "better_supabase"."bom_operations" ("tenant_id", "bom_id", "sequence", "work_center_id", "title", "setup_minutes", "run_minutes_per_unit", "instructions_node_id", "inspection_template")
  select save_bom.tenant, v_row."id", (e ->> 'sequence')::integer, (e ->> 'workCenterId')::uuid, trim(e ->> 'title'),
    coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0), coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0),
    nullif(e ->> 'instructionsNodeId', '')::uuid, nullif(e ->> 'inspectionTemplate', '')
  from jsonb_array_elements(v_operations) e;
  insert into "better_supabase"."bom_components" ("tenant_id", "bom_id", "position", "variant_id", "quantity", "scrap_bps", "operation_id")
  select save_bom.tenant, v_row."id", e.n::integer, (e.value ->> 'variantId')::uuid, (e.value ->> 'quantity')::numeric,
    coalesce(nullif(e.value ->> 'scrapBps', '')::integer, 0),
    (select y."id" from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id" and y."sequence" = nullif(e.value ->> 'operation', '')::integer)
  from jsonb_array_elements(v_components) with ordinality e(value, n);
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."save_bom"(uuid, uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_bom"(uuid, uuid, jsonb, uuid) to authenticated, service_role;

-- Makes a version its variant's active bill of materials; the version that was
-- active is archived. Refuses with BOM_CYCLE when the variant would end up in
-- its own components.
create or replace function "better_supabase"."activate_bom"(bom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."boms";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."boms" x where x."id" = activate_bom.bom_id for update;
  if not found then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'BOM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.manage'), false))) then
    raise exception 'not allowed to activate bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" = 'active' then
    return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
  end if;
  if exists (select 1 from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"
    and "better_supabase"."bom_reaches"(y."variant_id", v_row."variant_id")) then
    raise exception 'a component is made from the variant itself' using errcode = '22023', hint = 'BOM_CYCLE';
  end if;
  update "better_supabase"."boms" x set "status" = 'archived', "updated_at" = now()
  where x."variant_id" = v_row."variant_id" and x."status" = 'active';
  update "better_supabase"."boms" x set "status" = 'active', "activated_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."activate_bom"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_bom"(uuid) to authenticated, service_role;

-- A bill of materials version with its components and operations.
create or replace function "better_supabase"."get_bom"(bom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."boms";
begin
  select * into v_row from "better_supabase"."boms" x where x."id" = get_bom.bom_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'BOM_NOT_FOUND';
  end if;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."get_bom"(uuid) from public, anon;
grant execute on function "better_supabase"."get_bom"(uuid) to authenticated, service_role;

-- The organization's bill of materials versions, of one variant when variant
-- isn't null, the latest version first.
create or replace function "better_supabase"."list_boms"(tenant uuid, variant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_boms.tenant is not null and coalesce(better_supabase.can('tenant', list_boms.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."variant_id", x."version" desc)
    from "better_supabase"."boms" x where x."tenant_id" = list_boms.tenant
      and (list_boms.variant is null or x."variant_id" = list_boms.variant)), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_boms"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_boms"(uuid, uuid) to authenticated, service_role;

-- What making quantity of a variant takes, through the active bills of
-- materials at every level: { variantId, quantity, lines: [{ level,
-- variantId, parentVariantId, bomId, quantity, made }], materials: [{
-- variantId, quantity }] }. Planned scrap counts; materials are the lines no
-- active bill of materials makes. Refuses with BOM_NOT_ACTIVE when the
-- variant has no active bill of materials.
create or replace function "better_supabase"."explode_bom"(variant_id uuid, quantity numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (select cv."tenant_id" from "better_supabase"."product_variants" cv where cv."id" = explode_bom.variant_id);
  v_lines jsonb;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'BOM_NOT_FOUND';
  end if;
  if explode_bom.quantity is null or explode_bom.quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."boms" x where x."variant_id" = explode_bom.variant_id and x."status" = 'active') then
    raise exception 'the variant has no active bill of materials' using errcode = '55000', hint = 'BOM_NOT_ACTIVE';
  end if;
  with recursive tree(variant, parent, bom, quantity, level, path) as (
    select y."variant_id", x."variant_id", x."id",
      explode_bom.quantity * y."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0), 1,
      array[x."variant_id", y."variant_id"]
    from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where x."variant_id" = explode_bom.variant_id and x."status" = 'active'
    union all
    select y."variant_id", x."variant_id", x."id",
      tree.quantity * y."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0), tree.level + 1,
      tree.path || y."variant_id"
    from tree
    join "better_supabase"."boms" x on x."variant_id" = tree.variant and x."status" = 'active'
    join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where tree.level < 20 and not (y."variant_id" = any (tree.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('level', t.level, 'variantId', t.variant, 'parentVariantId', t.parent, 'bomId', t.bom,
      'quantity', "better_supabase"."production_quantity"(t.variant, t.quantity)::text,
      'made', exists (select 1 from "better_supabase"."boms" z where z."variant_id" = t.variant and z."status" = 'active'))
    order by t.path), '[]'::jsonb)
  into v_lines from tree t;
  return jsonb_build_object('variantId', explode_bom.variant_id, 'quantity', explode_bom.quantity::text, 'lines', v_lines,
    'materials', coalesce((select jsonb_agg(jsonb_build_object('variantId', m.variant, 'quantity', m.quantity::text) order by m.variant)
      from (select (e ->> 'variantId')::uuid as variant, sum((e ->> 'quantity')::numeric) as quantity
        from jsonb_array_elements(v_lines) e where not (e ->> 'made')::boolean group by 1) m), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."explode_bom"(uuid, numeric) from public, anon;
grant execute on function "better_supabase"."explode_bom"(uuid, numeric) to authenticated, service_role;

-- The bills of materials a variant goes into: directly in any version that
-- isn't archived (level 1), then up through active versions. Each row is {
-- level, bomId, variantId, version, status, quantity }.
create or replace function "better_supabase"."bom_where_used"(variant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (select cv."tenant_id" from "better_supabase"."product_variants" cv where cv."id" = bom_where_used.variant_id);
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'BOM_NOT_FOUND';
  end if;
  return coalesce((with recursive used(bom, variant, version, status, quantity, level, path) as (
    select x."id", x."variant_id", x."version", x."status", y."quantity", 1, array[y."variant_id", x."variant_id"]
    from "better_supabase"."bom_components" y join "better_supabase"."boms" x on x."id" = y."bom_id"
    where y."variant_id" = bom_where_used.variant_id and x."status" <> 'archived'
    union all
    select x."id", x."variant_id", x."version", x."status", y."quantity", used.level + 1, used.path || x."variant_id"
    from used
    join "better_supabase"."bom_components" y on y."variant_id" = used.variant
    join "better_supabase"."boms" x on x."id" = y."bom_id" and x."status" = 'active'
    where used.status = 'active' and used.level < 20 and not (x."variant_id" = any (used.path))
  )
  select jsonb_agg(jsonb_build_object('level', u.level, 'bomId', u.bom, 'variantId', u.variant, 'version', u.version,
    'status', u.status, 'quantity', u.quantity::text) order by u.level, u.variant, u.version desc) from used u), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."bom_where_used"(uuid) from public, anon;
grant execute on function "better_supabase"."bom_where_used"(uuid) to authenticated, service_role;

-- Creates a work center (work_center_id null) or changes one. input is {
-- name, assetId, hoursPerDay, costRate (minor units per hour), currency,
-- archived }; keys left out keep their value.
create or replace function "better_supabase"."save_work_center"(tenant uuid, input jsonb, work_center_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_centers";
  v_asset uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_work_center.tenant is not null and coalesce(better_supabase.can('tenant', save_work_center.tenant, 'manufacturing.manage'), false))) then
    raise exception 'not allowed to change work centers' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_work_center.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'BOM_INVALID';
  end if;
  if save_work_center.work_center_id is not null then
    select * into v_row from "better_supabase"."work_centers" x
    where x."id" = save_work_center.work_center_id and x."tenant_id" = save_work_center.tenant for update;
    if not found then
      raise exception 'no such work center in this organization' using errcode = 'P0002', hint = 'WORK_CENTER_NOT_FOUND';
    end if;
  end if;
  v_asset := case when save_work_center.input ? 'assetId' then nullif(save_work_center.input ->> 'assetId', '')::uuid else v_row."asset_id" end;
  
  if save_work_center.work_center_id is null then
    insert into "better_supabase"."work_centers" ("tenant_id", "name", "asset_id", "hours_per_day", "cost_rate", "currency")
    values (save_work_center.tenant, trim(save_work_center.input ->> 'name'), v_asset,
      coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, 8),
      coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, 0),
      upper(nullif(save_work_center.input ->> 'currency', '')))
    returning * into v_row;
  else
    update "better_supabase"."work_centers" x set
      "name" = case when save_work_center.input ? 'name' then trim(save_work_center.input ->> 'name') else x."name" end,
      "asset_id" = v_asset,
      "hours_per_day" = coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, x."hours_per_day"),
      "cost_rate" = coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, x."cost_rate"),
      "currency" = case when save_work_center.input ? 'currency' then upper(nullif(save_work_center.input ->> 'currency', '')) else x."currency" end,
      "archived_at" = case when not save_work_center.input ? 'archived' then x."archived_at"
        when (save_work_center.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) else null end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'assetId', v_row."asset_id", 'hoursPerDay', v_row."hours_per_day"::text, 'costRate', v_row."cost_rate"::text, 'currency', v_row."currency", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_work_center"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_work_center"(uuid, jsonb, uuid) to authenticated, service_role;

-- The organization's work centers by name, archived ones included.
create or replace function "better_supabase"."list_work_centers"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_work_centers.tenant is not null and coalesce(better_supabase.can('tenant', list_work_centers.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read work centers' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id")
    from "better_supabase"."work_centers" x where x."tenant_id" = list_work_centers.tenant), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_work_centers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_work_centers"(uuid) to authenticated, service_role;


-- Takes quantity of a component out of stock for a production order, from
-- the order's open allocation of the variant when it has one, and records
-- the consumption per lot (or serial) at its stock value. The caller checks
-- permissions and the order's status. Returns the stock movement.
create or replace function "better_supabase"."production_consume"(order_id uuid, variant uuid, quantity numeric, detail jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_order "better_supabase"."production_orders";
  v_allocation uuid;
  v_movement uuid;
  v_cost bigint;
  v_currency text;
  v_serials text[];
begin
  select * into v_order from "better_supabase"."production_orders" x where x."id" = production_consume.order_id;
  select x."id" into v_allocation from "better_supabase"."stock_allocations" x
  where x."tenant_id" = v_order."tenant_id" and x."document_type" = 'production_order'
    and x."document_id" = v_order."id"::text and x."variant_id" = production_consume.variant
    and x."status" = 'open' and x."quantity" - x."fulfilled" >= production_consume.quantity
  order by x."created_at", x."id"
  limit 1;
  if v_allocation is not null then
    v_movement := ("better_supabase"."take_allocation"(v_allocation, production_consume.quantity, 'consumption', production_consume.detail) ->> 'movementId')::uuid;
  else
    v_movement := "better_supabase"."move_stock"(v_order."tenant_id", production_consume.variant, v_order."location_id", -production_consume.quantity, 'consumption', 'production_order', v_order."id"::text, null, production_consume.detail);
  end if;
  select coalesce(-sum(e."amount"), 0), min(y."unit") into v_cost, v_currency
  from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" y on y."id" = e."account_id"
  where e."transaction_id" = v_movement and y."kind" = 'stock_value';
  if jsonb_typeof(production_consume.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(production_consume.detail -> 'serials'));
  end if;
  if coalesce(cardinality(v_serials), 0) > 0 then
    insert into "better_supabase"."production_consumptions" ("tenant_id", "order_id", "variant_id", "lot_id", "serial", "quantity", "cost", "currency", "movement_id", "created_by")
    select v_order."tenant_id", v_order."id", production_consume.variant,
      (select z."lot_id" from "better_supabase"."stock_serials" z where z."variant_id" = production_consume.variant and z."serial" = e.serial),
      e.serial, 1, round(v_cost * e.n / cardinality(v_serials)) - round(v_cost * (e.n - 1) / cardinality(v_serials)), v_currency, v_movement, auth.uid()
    from unnest(v_serials) with ordinality e(serial, n);
  else
    insert into "better_supabase"."production_consumptions" ("tenant_id", "order_id", "variant_id", "lot_id", "quantity", "cost", "currency", "movement_id", "created_by")
    select v_order."tenant_id", v_order."id", production_consume.variant, g.lot, g.quantity,
      round(v_cost * g.upto / production_consume.quantity) - round(v_cost * (g.upto - g.quantity) / production_consume.quantity),
      v_currency, v_movement, auth.uid()
    from (select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity,
        sum((p ->> 'quantity')::numeric) over (order by p ->> 'lotId' nulls last) as upto
      from jsonb_array_elements(coalesce((select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g), '[]'::jsonb)) p
      where (p ->> 'quantity')::numeric > 0) g;
  end if;
  return v_movement;
end;
$$;
revoke execute on function "better_supabase"."production_consume"(uuid, uuid, numeric, jsonb) from public, anon, authenticated;

-- Creates a draft production order: input is { variantId, quantity,
-- locationId, dueOn, bomId, note, fields }. It pins the variant's active
-- bill of materials (or bomId, which must be active) and takes its number
-- from the numbering block. locationId defaults to the first active location.
create or replace function "better_supabase"."create_production_order"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_variant uuid;
  v_quantity numeric;
  v_location uuid;
  v_bom uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_production_order.tenant is not null and coalesce(better_supabase.can('tenant', create_production_order.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to create production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_production_order.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_variant := nullif(create_production_order.input ->> 'variantId', '')::uuid;
  v_quantity := nullif(create_production_order.input ->> 'quantity', '')::numeric;
  if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = v_variant and cv."tenant_id" = create_production_order.tenant) then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_quantity is null or v_quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_location := nullif(create_production_order.input ->> 'locationId', '')::uuid;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    where y."tenant_id" = create_production_order.tenant and y."active"
    order by y."code"
    limit 1;
  end if;
  if v_location is null or not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location
    and y."tenant_id" = create_production_order.tenant and y."active") then
    raise exception 'the location isn''t an active location of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select x."id" into v_bom from "better_supabase"."boms" x
  where x."variant_id" = v_variant and x."status" = 'active'
    and (nullif(create_production_order.input ->> 'bomId', '') is null or x."id" = (create_production_order.input ->> 'bomId')::uuid);
  if v_bom is null then
    raise exception 'the variant has no active bill of materials' using errcode = '55000', hint = 'BOM_NOT_ACTIVE';
  end if;
  v_seq := "better_supabase"."next_number"(create_production_order.tenant, 'production_order', now());
  v_number := better_supabase.format_assigned_number('MO-{yyyy}-{n:4}', v_seq, now());
  insert into "better_supabase"."production_orders" ("tenant_id", "number", "sequence", "variant_id", "bom_id", "quantity", "location_id", "due_on", "note", "created_by")
  values (create_production_order.tenant, v_number, v_seq, v_variant, v_bom, v_quantity, v_location,
    nullif(create_production_order.input ->> 'dueOn', '')::date, nullif(trim(create_production_order.input ->> 'note'), ''), auth.uid())
  returning * into v_row;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."create_production_order"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_production_order"(uuid, jsonb) to authenticated, service_role;

-- Releases a draft production order to the floor: it copies the bill of
-- materials' operations with their planned minutes and allocates each
-- component's quantity (planned scrap included) at the order's location.
-- Refuses with PRODUCTION_ORDER_SHORTAGE when a component would go on
-- backorder, unless allow_shortage is true.
create or replace function "better_supabase"."release_production_order"(order_id uuid, allow_shortage boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_bom "better_supabase"."boms";
  v_component record;
  v_allocation jsonb;
  v_shortages jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_orders" x where x."id" = release_production_order.order_id for update;
  if not found then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.write'), false))) then
    raise exception 'not allowed to release production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the production order can''t move from % to %', v_row."status", 'released' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'released')::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_production_order_release"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_bom from "better_supabase"."boms" x where x."id" = v_row."bom_id";
  insert into "better_supabase"."production_order_operations" ("tenant_id", "order_id", "operation_id", "sequence", "work_center_id", "title", "planned_minutes")
  select v_row."tenant_id", v_row."id", y."id", y."sequence", y."work_center_id", y."title",
    round(y."setup_minutes" + y."run_minutes_per_unit" * v_row."quantity", 2)
  from "better_supabase"."bom_operations" y where y."bom_id" = v_bom."id";
  for v_component in
    select y."id" as id, y."variant_id" as variant,
      "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / v_bom."quantity" * (1 + y."scrap_bps" / 10000.0)) as quantity
    from "better_supabase"."bom_components" y where y."bom_id" = v_bom."id"
    order by y."position", y."id"
  loop
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_allocation := "better_supabase"."allocate_stock"(v_row."tenant_id", v_component.variant, v_row."location_id", v_component.quantity,
      'production_order', v_row."id"::text, v_component.id::text, true);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    if (v_allocation ->> 'backordered')::numeric > 0 then
      v_shortages := v_shortages || jsonb_build_array(jsonb_build_object('variantId', v_component.variant,
        'quantity', v_component.quantity::text, 'backordered', v_allocation ->> 'backordered'));
    end if;
  end loop;
  if jsonb_array_length(v_shortages) > 0 and not coalesce(release_production_order.allow_shortage, false) then
    raise exception 'not enough stock for the production order''s components' using errcode = '23514',
      hint = 'PRODUCTION_ORDER_SHORTAGE', detail = jsonb_build_object('shortages', v_shortages)::text;
  end if;
  update "better_supabase"."production_orders" x set "status" = 'released', "released_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_production_order_release"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."release_production_order"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."release_production_order"(uuid, boolean) to authenticated, service_role;

-- Starts an operation of a released production order; the order moves to
-- in progress. An operation with an inspection template schedules an
-- inspection of that kind with the order as its auditee.
create or replace function "better_supabase"."start_production_operation"(operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_order_operations";
  v_order "better_supabase"."production_orders";
  v_template text;
  v_inspection uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_order_operations" x where x."id" = start_production_operation.operation_id for update;
  if not found then
    raise exception 'no such production order operation' using errcode = 'P0002', hint = 'PRODUCTION_OPERATION_NOT_FOUND';
  end if;
  select * into v_order from "better_supabase"."production_orders" x where x."id" = v_row."order_id" for update;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_order."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_order."tenant_id", 'manufacturing.produce'), false))) then
    raise exception 'not allowed to run production operations' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_order."status" not in ('released', 'in_progress') then
    raise exception 'the production order can''t move from % to %', v_order."status", 'in_progress' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_order."status", 'to', 'in_progress')::text;
  end if;
  if v_row."status" <> 'pending' then
    raise exception 'the operation has already started' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  update "better_supabase"."production_order_operations" x set "status" = 'in_progress', "started_at" = now(), "operator_id" = auth.uid()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_order."status" = 'released' then
    update "better_supabase"."production_orders" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now()
    where x."id" = v_order."id"
    returning * into v_order;
  end if;
  select y."inspection_template" into v_template from "better_supabase"."bom_operations" y where y."id" = v_row."operation_id";
  
  return (jsonb_build_object('id', v_order."id", 'organizationId', v_order."tenant_id", 'number', v_order."number", 'variantId', v_order."variant_id", 'bomId', v_order."bom_id", 'quantity', v_order."quantity"::text, 'locationId', v_order."location_id", 'dueOn', v_order."due_on", 'status', v_order."status", 'producedQuantity', v_order."produced_quantity"::text, 'scrapQuantity', v_order."scrap_quantity"::text, 'outputLotId', v_order."output_lot_id", 'materialCost', v_order."material_cost"::text, 'laborCost', v_order."labor_cost"::text, 'currency', v_order."currency", 'note', v_order."note", 'releasedAt', v_order."released_at", 'startedAt', v_order."started_at", 'completedAt', v_order."completed_at", 'canceledAt', v_order."canceled_at", 'createdBy', v_order."created_by", 'createdAt', v_order."created_at", 'updatedAt', v_order."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_order."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_order."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_order."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_order."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_order."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_order."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_order."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."start_production_operation"(uuid) from public, anon;
grant execute on function "better_supabase"."start_production_operation"(uuid) to authenticated, service_role;

-- Finishes a started operation. minutes is the time worked; null takes the
-- time since it started.
create or replace function "better_supabase"."finish_production_operation"(operation_id uuid, minutes numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_order_operations";
  v_order "better_supabase"."production_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_order_operations" x where x."id" = finish_production_operation.operation_id for update;
  if not found then
    raise exception 'no such production order operation' using errcode = 'P0002', hint = 'PRODUCTION_OPERATION_NOT_FOUND';
  end if;
  select * into v_order from "better_supabase"."production_orders" x where x."id" = v_row."order_id" for update;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_order."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_order."tenant_id", 'manufacturing.produce'), false))) then
    raise exception 'not allowed to run production operations' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_progress' then
    raise exception 'only a started operation finishes' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if finish_production_operation.minutes is not null and finish_production_operation.minutes < 0 then
    raise exception 'minutes can''t be negative' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  update "better_supabase"."production_order_operations" x set "status" = 'done', "finished_at" = now(),
    "minutes" = round(coalesce(finish_production_operation.minutes, extract(epoch from now() - x."started_at") / 60), 2)
  where x."id" = v_row."id";
  return (jsonb_build_object('id', v_order."id", 'organizationId', v_order."tenant_id", 'number', v_order."number", 'variantId', v_order."variant_id", 'bomId', v_order."bom_id", 'quantity', v_order."quantity"::text, 'locationId', v_order."location_id", 'dueOn', v_order."due_on", 'status', v_order."status", 'producedQuantity', v_order."produced_quantity"::text, 'scrapQuantity', v_order."scrap_quantity"::text, 'outputLotId', v_order."output_lot_id", 'materialCost', v_order."material_cost"::text, 'laborCost', v_order."labor_cost"::text, 'currency', v_order."currency", 'note', v_order."note", 'releasedAt', v_order."released_at", 'startedAt', v_order."started_at", 'completedAt', v_order."completed_at", 'canceledAt', v_order."canceled_at", 'createdBy', v_order."created_by", 'createdAt', v_order."created_at", 'updatedAt', v_order."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_order."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_order."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_order."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_order."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_order."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_order."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_order."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."finish_production_operation"(uuid, numeric) from public, anon;
grant execute on function "better_supabase"."finish_production_operation"(uuid, numeric) to authenticated, service_role;

-- Records quantity of a component taken for a released production order.
-- detail picks the bin, lot or serial numbers, as for move_stock; without
-- one, stock leaves first-expiry-first-out.
create or replace function "better_supabase"."record_production_consumption"(order_id uuid, variant uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_orders" x where x."id" = record_production_consumption.order_id for update;
  if not found then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.produce'), false))) then
    raise exception 'not allowed to record production consumption' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" not in ('released', 'in_progress') then
    raise exception 'the production order can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  if record_production_consumption.variant is null or not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = record_production_consumption.variant and cv."tenant_id" = v_row."tenant_id") then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if record_production_consumption.quantity is null or record_production_consumption.quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  perform "better_supabase"."production_consume"(v_row."id", record_production_consumption.variant, record_production_consumption.quantity, record_production_consumption.detail);
  update "better_supabase"."production_orders" x set "status" = 'in_progress', "started_at" = coalesce(x."started_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."record_production_consumption"(uuid, uuid, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."record_production_consumption"(uuid, uuid, numeric, jsonb) to authenticated, service_role;

-- Completes a production order: produced goes into stock at the order's
-- location and scrap is recorded. Components with nothing recorded are
-- backflushed for produced plus scrap, the rest of the allocations is
-- released, and open operations finish at their planned minutes. The output
-- is valued at the consumed components' stock value plus the work centers'
-- labor. lot is { code, expiresOn } or { lotId }; a lot-tracked variant
-- without one gets a lot named after the order. The output lot links to
-- every lot the order consumed.
create or replace function "better_supabase"."complete_production_order"(order_id uuid, produced numeric, scrap numeric default 0, lot jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_bom "better_supabase"."boms";
  v_component record;
  v_tracking text;
  v_item_currency text;
  v_currency text;
  v_lot uuid;
  v_material bigint;
  v_labor bigint;
  v_scrap numeric := coalesce(complete_production_order.scrap, 0);
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_orders" x where x."id" = complete_production_order.order_id for update;
  if not found then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.produce'), false))) then
    raise exception 'not allowed to complete production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" not in ('released', 'in_progress') then
    raise exception 'the production order can''t move from % to %', v_row."status", 'done' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'done')::text;
  end if;
  if complete_production_order.produced is null or complete_production_order.produced <= 0 or v_scrap < 0 then
    raise exception 'produced must be more than zero and scrap zero or more' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if complete_production_order.lot is not null and jsonb_typeof(complete_production_order.lot) <> 'object' then
    raise exception 'lot must be an object' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_production_order_complete"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_bom from "better_supabase"."boms" x where x."id" = v_row."bom_id";
  for v_component in
    select y."variant_id" as variant,
      "better_supabase"."production_quantity"(y."variant_id", y."quantity" * (complete_production_order.produced + v_scrap) / v_bom."quantity" * (1 + y."scrap_bps" / 10000.0)) as quantity
    from "better_supabase"."bom_components" y where y."bom_id" = v_bom."id"
      and not exists (select 1 from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id" and z."variant_id" = y."variant_id")
    order by y."position", y."id"
  loop
    perform "better_supabase"."production_consume"(v_row."id", v_component.variant, v_component.quantity, null);
  end loop;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."release_allocations"(v_row."tenant_id", 'production_order', v_row."id"::text);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  update "better_supabase"."production_order_operations" x set "status" = 'done', "started_at" = coalesce(x."started_at", now()),
    "finished_at" = now(), "minutes" = coalesce(x."minutes", x."planned_minutes")
  where x."order_id" = v_row."id" and x."status" <> 'done';

  select x."tracking", x."currency" into v_tracking, v_item_currency
  from "better_supabase"."stock_items" x where x."variant_id" = v_row."variant_id";
  v_currency := coalesce(v_item_currency,
    (select min(z."currency") from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"),
    (select min(y."currency") from "better_supabase"."production_order_operations" x join "better_supabase"."work_centers" y on y."id" = x."work_center_id"
      where x."order_id" = v_row."id"));
  select coalesce(sum(z."cost"), 0) into v_material from "better_supabase"."production_consumptions" z
  where z."order_id" = v_row."id" and z."currency" is not distinct from v_currency;
  select coalesce(sum(round(x."minutes" * y."cost_rate" / 60.0)), 0)::bigint into v_labor
  from "better_supabase"."production_order_operations" x join "better_supabase"."work_centers" y on y."id" = x."work_center_id"
  where x."order_id" = v_row."id" and y."currency" = v_currency;

  v_lot := nullif(complete_production_order.lot ->> 'lotId', '')::uuid;
  if v_lot is null and (nullif(complete_production_order.lot ->> 'code', '') is not null or v_tracking = 'lot') then
    v_lot := "better_supabase"."stock_lot_for"(v_row."tenant_id", v_row."variant_id",
      coalesce(nullif(complete_production_order.lot ->> 'code', ''), v_row."number"),
      nullif(complete_production_order.lot ->> 'expiresOn', '')::date);
  end if;
  perform "better_supabase"."move_stock"(v_row."tenant_id", v_row."variant_id", v_row."location_id", complete_production_order.produced, 'production', 'production_order', v_row."id"::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_lot, 'serials', complete_production_order.lot -> 'serials',
      'unitCost', round((v_material + v_labor)::numeric / complete_production_order.produced, 6)::text, 'currency', v_item_currency)));
  if v_lot is not null then
    insert into "better_supabase"."stock_lot_links" ("tenant_id", "parent_lot_id", "child_lot_id", "order_id", "quantity")
    select v_row."tenant_id", v_lot, z."lot_id", v_row."id", sum(z."quantity")
    from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id" and z."lot_id" is not null and z."lot_id" <> v_lot
    group by z."lot_id";
  end if;
  update "better_supabase"."production_orders" x set "status" = 'done', "produced_quantity" = complete_production_order.produced, "scrap_quantity" = v_scrap,
    "output_lot_id" = v_lot, "material_cost" = v_material, "labor_cost" = v_labor, "currency" = v_currency,
    "started_at" = coalesce(x."started_at", now()), "completed_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_labor > 0 then
    null;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_production_order_complete"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."complete_production_order"(uuid, numeric, numeric, jsonb) from public, anon;
grant execute on function "better_supabase"."complete_production_order"(uuid, numeric, numeric, jsonb) to authenticated, service_role;

-- Cancels a production order that isn't done: its allocations are released
-- and the components it consumed go back into stock, the same lots and
-- serial numbers at the value they left at.
create or replace function "better_supabase"."cancel_production_order"(order_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_consumption record;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_orders" x where x."id" = cancel_production_order.order_id for update;
  if not found then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.write'), false))) then
    raise exception 'not allowed to cancel production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" not in ('draft', 'released', 'in_progress') then
    raise exception 'the production order can''t move from % to %', v_row."status", 'canceled' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'canceled')::text;
  end if;
  if cancel_production_order.reason is not null and length(cancel_production_order.reason) > 1000 then
    raise exception 'the reason is at most 1000 characters' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."release_allocations"(v_row."tenant_id", 'production_order', v_row."id"::text);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  for v_consumption in
    select z."variant_id" as variant, z."lot_id" as lot, z."currency" as currency,
      array_agg(z."serial") filter (where z."serial" is not null) as serials,
      sum(z."quantity") as quantity, sum(z."cost") as cost
    from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"
    group by z."variant_id", z."lot_id", z."currency"
  loop
    perform "better_supabase"."move_stock"(v_row."tenant_id", v_consumption.variant, v_row."location_id", v_consumption.quantity, 'consumption', 'production_order', v_row."id"::text, 'production order canceled', jsonb_strip_nulls(jsonb_build_object('lotId', v_consumption.lot, 'serials', to_jsonb(v_consumption.serials),
      'unitCost', case when v_consumption.currency is null then null else round(v_consumption.cost::numeric / v_consumption.quantity, 6)::text end,
      'currency', v_consumption.currency)));
  end loop;
  update "better_supabase"."production_orders" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."cancel_production_order"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_production_order"(uuid, text) to authenticated, service_role;

-- A production order with its operations, components and consumptions.
create or replace function "better_supabase"."get_production_order"(order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."production_orders";
begin
  select * into v_row from "better_supabase"."production_orders" x where x."id" = get_production_order.order_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false))) then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."get_production_order"(uuid) from public, anon;
grant execute on function "better_supabase"."get_production_order"(uuid) to authenticated, service_role;

-- The organization's production orders, due first: filter is { status,
-- variantId, limit } (limit 1 to 500, default 100).
create or replace function "better_supabase"."list_production_orders"(tenant uuid, filter jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_production_orders.tenant is not null and coalesce(better_supabase.can('tenant', list_production_orders.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."due_on" nulls last, x."sequence" desc)
    from (select * from "better_supabase"."production_orders" y where y."tenant_id" = list_production_orders.tenant
      and (nullif(list_production_orders.filter ->> 'status', '') is null or y."status" = list_production_orders.filter ->> 'status')
      and (nullif(list_production_orders.filter ->> 'variantId', '') is null or y."variant_id" = (list_production_orders.filter ->> 'variantId')::uuid)
      order by y."due_on" nulls last, y."sequence" desc
      limit least(greatest(coalesce(nullif(list_production_orders.filter ->> 'limit', '')::integer, 100), 1), 500)) x), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_production_orders"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_production_orders"(uuid, jsonb) to authenticated, service_role;


-- The lots a lot was made from (direction down) or the lots made from it
-- (direction up), at every level: { lotId, direction, lots: [{ level,
-- lotId, code, variantId, expiresOn, fromLotId, orderId, quantity }] }.
create or replace function "better_supabase"."lot_genealogy"(lot_id uuid, direction text default 'down')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."stock_lots" x where x."id" = lot_genealogy.lot_id;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such lot' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if lot_genealogy.direction is null or lot_genealogy.direction not in ('up', 'down') then
    raise exception 'direction is up or down' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  return jsonb_build_object('lotId', lot_genealogy.lot_id, 'direction', lot_genealogy.direction,
    'lots', coalesce((with recursive tree(lot, from_lot, order_id, quantity, level, path) as (
      select case when lot_genealogy.direction = 'down' then y."child_lot_id" else y."parent_lot_id" end, lot_genealogy.lot_id,
        y."order_id", y."quantity", 1, array[lot_genealogy.lot_id]
      from "better_supabase"."stock_lot_links" y
      where (lot_genealogy.direction = 'down' and y."parent_lot_id" = lot_genealogy.lot_id)
        or (lot_genealogy.direction = 'up' and y."child_lot_id" = lot_genealogy.lot_id)
      union all
      select case when lot_genealogy.direction = 'down' then y."child_lot_id" else y."parent_lot_id" end, tree.lot,
        y."order_id", y."quantity", tree.level + 1, tree.path || tree.lot
      from tree join "better_supabase"."stock_lot_links" y
        on (lot_genealogy.direction = 'down' and y."parent_lot_id" = tree.lot)
        or (lot_genealogy.direction = 'up' and y."child_lot_id" = tree.lot)
      where tree.level < 20 and not (tree.lot = any (tree.path))
    )
    select jsonb_agg(jsonb_build_object('lotId', l."id", 'code', l."code", 'variantId', l."variant_id", 'expiresOn', l."expires_on") || jsonb_build_object('level', t.level, 'fromLotId', t.from_lot, 'orderId', t.order_id,
      'quantity', t.quantity::text) order by t.level, l."code")
    from tree t join "better_supabase"."stock_lots" l on l."id" = t.lot), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."lot_genealogy"(uuid, text) from public, anon;
grant execute on function "better_supabase"."lot_genealogy"(uuid, text) to authenticated, service_role;

-- What a recall of a lot reaches: the lot and every lot made from it, the
-- stock of those lots still on hand, the documents they left stock for (a
-- sale's order or shipment) and the production orders that consumed them.
create or replace function "better_supabase"."lot_recall"(lot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_lots uuid[];
begin
  select x."tenant_id" into v_tenant from "better_supabase"."stock_lots" x where x."id" = lot_recall.lot_id;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such lot' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  with recursive up(lot, level, path) as (
    select lot_recall.lot_id, 0, array[lot_recall.lot_id]
    union all
    select y."parent_lot_id", up.level + 1, up.path || y."parent_lot_id"
    from up join "better_supabase"."stock_lot_links" y on y."child_lot_id" = up.lot
    where up.level < 20 and not (y."parent_lot_id" = any (up.path))
  )
  select array_agg(distinct up.lot) into v_lots from up;
  return jsonb_build_object('lotId', lot_recall.lot_id,
    'lots', coalesce((select jsonb_agg(jsonb_build_object('lotId', l."id", 'code', l."code", 'variantId', l."variant_id", 'expiresOn', l."expires_on") order by l."code") from "better_supabase"."stock_lots" l where l."id" = any (v_lots)), '[]'::jsonb),
    'stock', coalesce((select jsonb_agg(jsonb_build_object('lotId', y."lot_id", 'variantId', y."variant_id", 'locationId', y."location_id",
        'binId', y."bin_id", 'onHand', y."on_hand"::text) order by y."lot_id", y."location_id")
      from "better_supabase"."stock_buckets" y where y."lot_id" = any (v_lots) and y."on_hand" > 0), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('referenceType', d.reference_type, 'referenceId', d.reference_id,
        'lotId', d.lot, 'variantId', d.variant, 'quantity', d.quantity::text, 'at', d.at) order by d.at, d.reference_id)
      from (select t."reference_type" as reference_type, t."reference_id" as reference_id,
          (y."metadata" ->> 'lotId')::uuid as lot, (y."metadata" ->> 'variantId')::uuid as variant,
          sum(-e."amount" / power(10::numeric, y."scale")) as quantity, min(t."effective_at") as at
        from "better_supabase"."ledger_transactions" t
        join "better_supabase"."ledger_entries" e on e."transaction_id" = t."id"
        join "better_supabase"."ledger_accounts" y on y."id" = e."account_id" and y."kind" = 'stock'
        where t."tenant_id" = v_tenant and t."kind" in ('stock.sale', 'stock.transfer_out') and t."reference_id" is not null
          and (y."metadata" ->> 'lotId')::uuid = any (v_lots)
        group by 1, 2, 3, 4
        having sum(-e."amount") > 0) d), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('orderId', o."id", 'number', o."number", 'status', o."status",
        'variantId', o."variant_id", 'outputLotId', o."output_lot_id") order by o."number")
      from "better_supabase"."production_orders" o where o."status" <> 'canceled'
        and exists (select 1 from "better_supabase"."production_consumptions" z where z."order_id" = o."id" and z."lot_id" = any (v_lots))), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."lot_recall"(uuid) from public, anon;
grant execute on function "better_supabase"."lot_recall"(uuid) to authenticated, service_role;

-- One netting pass of material requirements: per variant the demand
-- (backorders, components of draft production orders due within the
-- horizon, and extra, a { variantId: quantity } map), the supply (available,
-- incoming, production orders not done) and the reorder point. A variant
-- whose projected stock ends below its reorder point (or zero) gets a
-- suggestion: produce when it has an active bill of materials, else
-- purchase.
create or replace function "better_supabase"."requirements_pass"(tenant uuid, horizon_days integer, extra jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with horizon as (select current_date + greatest(coalesce(requirements_pass.horizon_days, 30), 0) as until),
  levels as (
    select x."variant_id" as variant, sum(x."available") as available, sum(x."incoming") as incoming,
      sum(x."reorder_point") as reorder_point
    from "better_supabase"."stock_levels" x where x."tenant_id" = requirements_pass.tenant
    group by 1
  ),
  backorders as (
    select x."variant_id" as variant, sum(x."backordered") as quantity
    from "better_supabase"."stock_allocations" x
    where x."tenant_id" = requirements_pass.tenant and x."status" = 'open' and x."backordered" > 0
    group by 1
  ),
  draft_needs as (
    select y."variant_id" as variant,
      sum("better_supabase"."production_quantity"(y."variant_id", y."quantity" * o."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))) as quantity
    from "better_supabase"."production_orders" o
    join "better_supabase"."boms" x on x."id" = o."bom_id"
    join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where o."tenant_id" = requirements_pass.tenant and o."status" = 'draft'
      and (o."due_on" is null or o."due_on" <= (select until from horizon))
    group by 1
  ),
  planned as (
    select o."variant_id" as variant, sum(o."quantity" - o."produced_quantity") as quantity
    from "better_supabase"."production_orders" o
    where o."tenant_id" = requirements_pass.tenant and o."status" in ('draft', 'released', 'in_progress')
      and (o."due_on" is null or o."due_on" <= (select until from horizon))
    group by 1
  ),
  extras as (
    select e.key::uuid as variant, e.value::numeric as quantity
    from jsonb_each_text(coalesce(requirements_pass.extra, '{}'::jsonb)) e
  ),
  variants as (
    select variant from levels union select variant from backorders union select variant from draft_needs
    union select variant from extras
  ),
  net as (
    select v.variant, coalesce(l.available, 0) as available, coalesce(l.incoming, 0) as incoming,
      coalesce(p.quantity, 0) as planned, l.reorder_point,
      coalesce(bo.quantity, 0) + coalesce(d.quantity, 0) + coalesce(e.quantity, 0) as demand,
      (select x."id" from "better_supabase"."boms" x where x."variant_id" = v.variant and x."status" = 'active') as bom
    from variants v
    left join levels l on l.variant = v.variant
    left join backorders bo on bo.variant = v.variant
    left join draft_needs d on d.variant = v.variant
    left join planned p on p.variant = v.variant
    left join extras e on e.variant = v.variant
  )
  select coalesce(jsonb_agg(jsonb_build_object('variantId', n.variant, 'action', case when n.bom is null then 'purchase' else 'produce' end,
      'bomId', n.bom, 'quantity', "better_supabase"."production_quantity"(n.variant, coalesce(n.reorder_point, 0) - (n.available + n.incoming + n.planned - n.demand))::text,
      'available', n.available::text, 'incoming', n.incoming::text, 'planned', n.planned::text, 'demand', n.demand::text,
      'reorderPoint', n.reorder_point::text) order by n.variant), '[]'::jsonb)
  from net n
  where coalesce(n.reorder_point, 0) - (n.available + n.incoming + n.planned - n.demand) > 0;
$$;
revoke execute on function "better_supabase"."requirements_pass"(uuid, integer, jsonb) from public, anon, authenticated;

-- What the organization has to produce or buy to cover its demand within
-- horizon_days: { organizationId, horizonDays, items: [{ variantId, action,
-- bomId, quantity, available, incoming, planned, demand, reorderPoint }] }.
-- A produce suggestion adds its components' quantities to their demand, so
-- every level of the bills of materials is netted.
create or replace function "better_supabase"."material_requirements"(tenant uuid, horizon_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_items jsonb;
  v_extra jsonb := '{}'::jsonb;
  v_next jsonb;
  v_pass integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (material_requirements.tenant is not null and coalesce(better_supabase.can('tenant', material_requirements.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read material requirements' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if material_requirements.horizon_days is not null and material_requirements.horizon_days not between 0 and 3650 then
    raise exception 'horizon_days is 0 to 3650' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  loop
    v_items := "better_supabase"."requirements_pass"(material_requirements.tenant, material_requirements.horizon_days, v_extra);
    select coalesce(jsonb_object_agg(g.variant, g.quantity::text), '{}'::jsonb) into v_next
    from (select y."variant_id"::text as variant,
        sum(y."quantity" * (i ->> 'quantity')::numeric / x."quantity" * (1 + y."scrap_bps" / 10000.0)) as quantity
      from jsonb_array_elements(v_items) i
      join "better_supabase"."boms" x on x."id" = (i ->> 'bomId')::uuid
      join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      where i ->> 'action' = 'produce'
      group by 1) g;
    v_pass := v_pass + 1;
    exit when v_next = v_extra or v_pass > 20;
    v_extra := v_next;
  end loop;
  return jsonb_build_object('organizationId', material_requirements.tenant,
    'horizonDays', coalesce(material_requirements.horizon_days, 30), 'items', v_items);
end;
$$;
revoke execute on function "better_supabase"."material_requirements"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."material_requirements"(uuid, integer) to authenticated, service_role;

-- Turns material requirement suggestions into documents: items is [{
-- variantId, action, quantity, dueOn, locationId }]; a produce item becomes
-- a draft production order, purchase items become draft purchase orders of
-- the inventory block, one per location, supplier ({ supplierType,
-- supplierId }) and currency, at unitCost or the variant's average cost.
-- Returns { productionOrders, purchaseOrders }.
create or replace function "better_supabase"."create_from_requirements"(tenant uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_orders jsonb := '[]'::jsonb;
  v_purchases jsonb := '[]'::jsonb;
  v_purchase jsonb;
  v_group record;
  v_default_location uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_from_requirements.tenant is not null and coalesce(better_supabase.can('tenant', create_from_requirements.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to plan production' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_from_requirements.items) is distinct from 'array' or jsonb_array_length(create_from_requirements.items) = 0 then
    raise exception 'items must be a non-empty array' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(create_from_requirements.items) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'action', '') not in ('produce', 'purchase')
      or nullif(e ->> 'variantId', '') is null or coalesce(nullif(e ->> 'quantity', '')::numeric, 0) <= 0) then
    raise exception 'each item has a variantId, an action of produce or purchase and a quantity above zero' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select y."id" into v_default_location from "better_supabase"."inventory_locations" y
  where y."tenant_id" = create_from_requirements.tenant and y."active"
  order by y."code"
  limit 1;
  for v_item in
    select e from jsonb_array_elements(create_from_requirements.items) e where e ->> 'action' = 'produce'
  loop
    v_orders := v_orders || jsonb_build_array("better_supabase"."create_production_order"(create_from_requirements.tenant,
      jsonb_strip_nulls(jsonb_build_object('variantId', v_item ->> 'variantId', 'quantity', v_item ->> 'quantity',
        'dueOn', v_item ->> 'dueOn', 'locationId', v_item ->> 'locationId'))));
  end loop;
  for v_group in
    select coalesce(nullif(e ->> 'locationId', '')::uuid, v_default_location) as location,
      nullif(e ->> 'supplierType', '') as supplier_type, nullif(e ->> 'supplierId', '') as supplier_id,
      upper(coalesce(nullif(e ->> 'currency', ''), (select y."currency" from "better_supabase"."stock_items" y where y."variant_id" = (e ->> 'variantId')::uuid))) as currency,
      jsonb_agg(jsonb_build_object('variantId', e ->> 'variantId', 'quantity', e ->> 'quantity',
        'unitCost', coalesce(nullif(e ->> 'unitCost', ''), (select round(coalesce(y."average_cost", 0))::bigint::text
          from "better_supabase"."stock_items" y where y."variant_id" = (e ->> 'variantId')::uuid), '0'))) as lines
    from jsonb_array_elements(create_from_requirements.items) e
    where e ->> 'action' = 'purchase'
    group by 1, 2, 3, 4
  loop
    if v_group.currency is null then
      raise exception 'a purchase suggestion needs a currency: set one on the item or the variant''s costing' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
    end if;
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_purchase := "better_supabase"."save_purchase_order"(create_from_requirements.tenant, null, v_group.location, v_group.supplier_type,
      v_group.supplier_id, v_group.currency, null, v_group.lines, 'From material requirements');
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    v_purchases := v_purchases || jsonb_build_array(v_purchase);
  end loop;
  return jsonb_build_object('productionOrders', v_orders, 'purchaseOrders', v_purchases);
end;
$$;
revoke execute on function "better_supabase"."create_from_requirements"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_from_requirements"(uuid, jsonb) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."boms";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."boms";
create policy bsb_tenant_scope_select on "better_supabase"."boms" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."boms";
create policy bsb_tenant_scope_insert on "better_supabase"."boms" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."boms";
create policy bsb_tenant_scope_update on "better_supabase"."boms" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."boms";
create policy bsb_tenant_scope_delete on "better_supabase"."boms" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."work_centers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."work_centers";
create policy bsb_tenant_scope_select on "better_supabase"."work_centers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."work_centers";
create policy bsb_tenant_scope_insert on "better_supabase"."work_centers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."work_centers";
create policy bsb_tenant_scope_update on "better_supabase"."work_centers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."work_centers";
create policy bsb_tenant_scope_delete on "better_supabase"."work_centers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bom_operations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bom_operations";
create policy bsb_tenant_scope_select on "better_supabase"."bom_operations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bom_operations";
create policy bsb_tenant_scope_insert on "better_supabase"."bom_operations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bom_operations";
create policy bsb_tenant_scope_update on "better_supabase"."bom_operations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bom_operations";
create policy bsb_tenant_scope_delete on "better_supabase"."bom_operations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bom_components";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bom_components";
create policy bsb_tenant_scope_select on "better_supabase"."bom_components" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bom_components";
create policy bsb_tenant_scope_insert on "better_supabase"."bom_components" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bom_components";
create policy bsb_tenant_scope_update on "better_supabase"."bom_components" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bom_components";
create policy bsb_tenant_scope_delete on "better_supabase"."bom_components" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."production_orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_orders";
create policy bsb_tenant_scope_select on "better_supabase"."production_orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_orders";
create policy bsb_tenant_scope_insert on "better_supabase"."production_orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_orders";
create policy bsb_tenant_scope_update on "better_supabase"."production_orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_orders";
create policy bsb_tenant_scope_delete on "better_supabase"."production_orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."production_order_operations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_order_operations";
create policy bsb_tenant_scope_select on "better_supabase"."production_order_operations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_order_operations";
create policy bsb_tenant_scope_insert on "better_supabase"."production_order_operations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_order_operations";
create policy bsb_tenant_scope_update on "better_supabase"."production_order_operations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_order_operations";
create policy bsb_tenant_scope_delete on "better_supabase"."production_order_operations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."production_consumptions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."production_consumptions";
create policy bsb_tenant_scope_select on "better_supabase"."production_consumptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."production_consumptions";
create policy bsb_tenant_scope_insert on "better_supabase"."production_consumptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."production_consumptions";
create policy bsb_tenant_scope_update on "better_supabase"."production_consumptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."production_consumptions";
create policy bsb_tenant_scope_delete on "better_supabase"."production_consumptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."stock_lot_links";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."stock_lot_links";
create policy bsb_tenant_scope_select on "better_supabase"."stock_lot_links" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('manufacturing.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."stock_lot_links";
create policy bsb_tenant_scope_insert on "better_supabase"."stock_lot_links" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."stock_lot_links";
create policy bsb_tenant_scope_update on "better_supabase"."stock_lot_links" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."stock_lot_links";
create policy bsb_tenant_scope_delete on "better_supabase"."stock_lot_links" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_154_manufacturing.sql
-- better-supabase module: manufacturing
-- @bsb-block-data manufacturing
-- @bsb-hash sha256:18e97e8f7006d8439ff170eb5ff50bad4ae04bd0bce4957faa697bb6da3b3dd2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
