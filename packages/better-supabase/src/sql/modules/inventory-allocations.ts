import type { BlockSqlContext } from "../context.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, userGrant } from "../shared.ts";
import {
  columns,
  guard,
  locationsOf,
  moveStock,
  strict,
} from "./inventory-stock.ts";
import { QUANTITY } from "./inventory-tracking.ts";

/** The states of a stock allocation. */
const ALLOCATION_STATUSES = ["open", "fulfilled", "released"] as const;

/** The allocations table, for the module's names. */
export const ALLOCATION_TABLES = {
  allocations: {
    name: "stock_allocations",
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      variant: "variant_id",
      location: "location_id",
      documentType: "document_type",
      documentId: "document_id",
      line: "line_id",
      quantity: "quantity",
      allocated: "allocated",
      fulfilled: "fulfilled",
      backordered: "backordered",
      status: "status",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
} as const;

export function allocationTable(
  ctx: BlockSqlContext,
  read: (table: string) => string,
  lock: (table: string) => string,
): string {
  const catalog = ctx.of("catalog");
  const loc = locationsOf(ctx);
  const a = columns(ctx, "allocations");
  const t = ctx.table("allocations");

  return `
create table if not exists ${t} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("variant")} uuid not null references ${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete cascade,
  ${a("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${a("documentType")} text not null check (${a("documentType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${a("documentId")} text not null check (length(${a("documentId")}) between 1 and 200),
  ${a("line")} text,
  ${a("quantity")} ${QUANTITY} not null check (${a("quantity")} > 0),
  ${a("allocated")} ${QUANTITY} not null default 0 check (${a("allocated")} >= 0),
  ${a("fulfilled")} ${QUANTITY} not null default 0 check (${a("fulfilled")} >= 0),
  ${a("backordered")} ${QUANTITY} generated always as (case when ${a("status")} = 'open' then ${a("quantity")} - ${a("allocated")} - ${a("fulfilled")} else 0 end) stored,
  ${a("status")} text not null default 'open' check (${a("status")} in (${ALLOCATION_STATUSES.map((value) => `'${value}'`).join(", ")})),
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  check (${a("allocated")} + ${a("fulfilled")} <= ${a("quantity")})
);
create index if not exists stock_allocations_document_idx on ${t} (${a("tenant")}, ${a("documentType")}, ${a("documentId")});
create index if not exists stock_allocations_open_idx on ${t} (${a("variant")}, ${a("location")}, ${a("createdAt")}) where ${a("status")} = 'open';
create index if not exists stock_allocations_location_idx on ${t} (${a("location")});
create index if not exists stock_allocations_variant_idx on ${t} (${a("variant")});
${lock("allocations")}
${read("allocations")}
`;
}

/** The JSON of allocation row `alias`. */
function allocationJson(ctx: BlockSqlContext, alias: string): string {
  const a = columns(ctx, "allocations");

  return `jsonb_build_object('id', ${alias}.${a("id")}, 'variantId', ${alias}.${a("variant")}, 'locationId', ${alias}.${a("location")},
    'documentType', ${alias}.${a("documentType")}, 'documentId', ${alias}.${a("documentId")}, 'lineId', ${alias}.${a("line")},
    'quantity', ${alias}.${a("quantity")}::text, 'allocated', ${alias}.${a("allocated")}::text, 'fulfilled', ${alias}.${a("fulfilled")}::text,
    'backordered', ${alias}.${a("backordered")}::text, 'status', ${alias}.${a("status")}, 'createdAt', ${alias}.${a("createdAt")})`;
}

/**
 * Stock a document (an order, a work order, a shipment) holds for its lines. An
 * allocation takes what's available and keeps the rest on backorder; stock that
 * arrives later fills backorders oldest first (ADR 0127).
 */
export function allocationFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const allocations = ctx.table("allocations");
  const levels = ctx.table("levels");
  const loc = locationsOf(ctx);
  const l = loc.col;
  const a = columns(ctx, "allocations");
  const lv = columns(ctx, "levels");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  const event = (type: string, row: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.tenant, 'id', ${row}.id, 'variantId', ${row}.variant, 'locationId', ${row}.location,
        'documentType', ${row}.document_type, 'documentId', ${row}.document_id, 'quantity', ${row}.quantity::text${extra})`,
      subject: `'stock-allocations/' || ${row}.id::text`,
      tenant: `${row}.tenant`,
      audit: false,
    });

  const load = (
    name: string,
  ): string => `select x.${a("id")} as id, x.${a("tenant")} as tenant, x.${a("variant")} as variant, x.${a("location")} as location,
    x.${a("documentType")} as document_type, x.${a("documentId")} as document_id, x.${a("quantity")} as quantity,
    x.${a("allocated")} as allocated, x.${a("fulfilled")} as fulfilled, x.${a("status")} as status
  into v_row from ${allocations} x where x.${a("id")} = ${name}.allocation for update;
  if not found then
    ${fail("INVENTORY_ALLOCATION_NOT_FOUND", "allocation not found", "P0002")}
  end if;
  ${guard(names.scope, names.reserve, "v_row.tenant")}`;

  const reserve = (variant: string, location: string, delta: string): string =>
    `update ${levels} x set ${lv("reserved")} = greatest(x.${lv("reserved")} + ${delta}, 0), ${lv("updatedAt")} = now()
    where x.${lv("variant")} = ${variant} and x.${lv("location")} = ${location};`;

  return `
-- Gives open backorders of a variant at a location the stock that became
-- available, oldest allocation first. Returns how much it allocated.
create or replace function ${fn("fill_backorders")}(tenant ${ctx.idType}, variant uuid, location uuid)
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
  select x.${lv("available")} into v_available from ${levels} x
  where x.${lv("variant")} = fill_backorders.variant and x.${lv("location")} = fill_backorders.location for update;
  if coalesce(v_available, 0) <= 0 then
    return 0;
  end if;
  for v_row in
    select x.${a("id")} as id, x.${a("tenant")} as tenant, x.${a("variant")} as variant, x.${a("location")} as location,
      x.${a("documentType")} as document_type, x.${a("documentId")} as document_id, x.${a("backordered")} as quantity
    from ${allocations} x
    where x.${a("variant")} = fill_backorders.variant and x.${a("location")} = fill_backorders.location
      and x.${a("status")} = 'open' and x.${a("backordered")} > 0
    order by x.${a("createdAt")}, x.${a("id")}
    for update
  loop
    exit when v_available <= 0;
    v_take := least(v_available, v_row.quantity);
    update ${allocations} x set ${a("allocated")} = x.${a("allocated")} + v_take, ${a("updatedAt")} = now() where x.${a("id")} = v_row.id;
    v_available := v_available - v_take;
    v_total := v_total + v_take;
    ${event("allocation.filled", "v_row", ", 'allocated', v_take::text")}
  end loop;
  if v_total > 0 then
    ${reserve("fill_backorders.variant", "fill_backorders.location", "v_total")}
  end if;
  return v_total;
end;
$$;
revoke execute on function ${fn("fill_backorders")}(${ctx.idType}, uuid, uuid) from public, anon, authenticated;

-- Allocates stock of a variant to a document line. location null picks the
-- active location with the most available. What isn't available stays on
-- backorder; backorder false raises INVENTORY_INSUFFICIENT instead for a
-- variant that can't go below zero. Returns the allocation.
create or replace function ${fn("allocate_stock")}(tenant ${ctx.idType}, variant uuid, location uuid, quantity numeric, document_type text, document_id text, line_id text, backorder boolean default true)
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
  ${guard(names.scope, names.reserve, "allocate_stock.tenant")}
  if not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = allocate_stock.variant and cv.${v("tenant")} = allocate_stock.tenant) then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "variant not found in this organization", "P0002")}
  end if;
  if allocate_stock.quantity is null or allocate_stock.quantity <= 0 then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must be greater than zero", "22023")}
  end if;
  if allocate_stock.document_type is null or allocate_stock.document_id is null then
    ${fail("INVENTORY_DOCUMENT_INVALID", "an allocation names its document type and id", "22023")}
  end if;
  if v_location is null then
    select y.${l("id")} into v_location from ${loc.table} y
    left join ${levels} s on s.${lv("location")} = y.${l("id")} and s.${lv("variant")} = allocate_stock.variant
    where y.${l("tenant")} = allocate_stock.tenant and ${loc.active("y")}
    order by coalesce(s.${lv("available")}, 0) desc, y.${l("code")}
    limit 1;
    if v_location is null then
      ${fail("INVENTORY_LOCATION_NOT_FOUND", "the organization has no active location", "P0002")}
    end if;
  elsif not exists (select 1 from ${loc.table} y where y.${l("id")} = v_location and y.${l("tenant")} = allocate_stock.tenant and ${loc.active("y")}) then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found or inactive", "P0002")}
  end if;
  insert into ${levels} (${lv("tenant")}, ${lv("variant")}, ${lv("location")})
  values (allocate_stock.tenant, allocate_stock.variant, v_location)
  on conflict (${lv("variant")}, ${lv("location")}) do nothing;
  select x.${lv("available")} into v_available from ${levels} x
  where x.${lv("variant")} = allocate_stock.variant and x.${lv("location")} = v_location for update;
  v_take := least(allocate_stock.quantity, greatest(v_available, 0));
  if v_take < allocate_stock.quantity and not coalesce(allocate_stock.backorder, true) and ${strict(ctx, "allocate_stock.variant")} then
    ${fail("INVENTORY_INSUFFICIENT", "not enough stock available", "23514")}
  end if;
  insert into ${allocations} as x (${a("tenant")}, ${a("variant")}, ${a("location")}, ${a("documentType")}, ${a("documentId")}, ${a("line")}, ${a("quantity")}, ${a("allocated")})
  values (allocate_stock.tenant, allocate_stock.variant, v_location, allocate_stock.document_type, allocate_stock.document_id,
    allocate_stock.line_id, allocate_stock.quantity, v_take)
  returning x.${a("id")} as id, x.${a("tenant")} as tenant, x.${a("variant")} as variant, x.${a("location")} as location,
    x.${a("documentType")} as document_type, x.${a("documentId")} as document_id, x.${a("quantity")} as quantity
  into v_row;
  if v_take > 0 then
    ${reserve("allocate_stock.variant", "v_location", "v_take")}
  end if;
  ${event("allocation.created", "v_row", ", 'allocated', v_take::text")}
  return (select ${allocationJson(ctx, "x")} from ${allocations} x where x.${a("id")} = v_row.id);
end;
$$;
${userGrant(`${fn("allocate_stock")}(${ctx.idType}, uuid, uuid, numeric, text, text, text, boolean)`)}

-- Takes quantity of an allocation out of stock as a sale, first from what it
-- holds, then from what's available. detail picks the bin, lot or serial
-- numbers, as for move_stock. Returns the allocation and the movement id.
create or replace function ${fn("fulfill_allocation")}(allocation uuid, quantity numeric, detail jsonb default null)
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
  ${load("fulfill_allocation")}
  if v_row.status <> 'open' then
    ${fail("INVENTORY_ALLOCATION_CLOSED", "the allocation is no longer open", "55000")}
  end if;
  if fulfill_allocation.quantity is null or fulfill_allocation.quantity <= 0
    or fulfill_allocation.quantity > v_row.quantity - v_row.fulfilled then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must be more than zero and at most what the allocation has left", "22023")}
  end if;
  v_from_held := least(fulfill_allocation.quantity, v_row.allocated);
  ${reserve("v_row.variant", "v_row.location", "-v_from_held")}
  update ${allocations} x set ${a("allocated")} = x.${a("allocated")} - v_from_held,
    ${a("fulfilled")} = x.${a("fulfilled")} + fulfill_allocation.quantity,
    ${a("status")} = case when x.${a("fulfilled")} + fulfill_allocation.quantity >= x.${a("quantity")} then 'fulfilled' else 'open' end,
    ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.id;
  v_movement := ${moveStock(ctx, { tenant: "v_row.tenant", variant: "v_row.variant", location: "v_row.location", quantity: "-fulfill_allocation.quantity", reason: "'sale'", referenceType: "v_row.document_type", referenceId: "v_row.document_id", detail: "fulfill_allocation.detail" })};
  return (select ${allocationJson(ctx, "x")} || jsonb_build_object('movementId', v_movement) from ${allocations} x where x.${a("id")} = v_row.id);
end;
$$;
${userGrant(`${fn("fulfill_allocation")}(uuid, numeric, jsonb)`)}

-- Puts fulfilled stock of an allocation back, as a return movement: a
-- cancelled shipment. The allocation reopens and the stock fills it (or an
-- older backorder) again. Returns the allocation and the movement id.
create or replace function ${fn("restore_allocation")}(allocation uuid, quantity numeric, detail jsonb default null)
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
  ${load("restore_allocation")}
  if v_row.status = 'released' then
    ${fail("INVENTORY_ALLOCATION_CLOSED", "the allocation was released", "55000")}
  end if;
  if restore_allocation.quantity is null or restore_allocation.quantity <= 0 or restore_allocation.quantity > v_row.fulfilled then
    ${fail("INVENTORY_QUANTITY_INVALID", "the quantity must be more than zero and at most what was fulfilled", "22023")}
  end if;
  update ${allocations} x set ${a("fulfilled")} = x.${a("fulfilled")} - restore_allocation.quantity, ${a("status")} = 'open', ${a("updatedAt")} = now()
  where x.${a("id")} = v_row.id;
  v_movement := ${moveStock(ctx, { tenant: "v_row.tenant", variant: "v_row.variant", location: "v_row.location", quantity: "restore_allocation.quantity", reason: "'return'", referenceType: "v_row.document_type", referenceId: "v_row.document_id", detail: "restore_allocation.detail" })};
  return (select ${allocationJson(ctx, "x")} || jsonb_build_object('movementId', v_movement) from ${allocations} x where x.${a("id")} = v_row.id);
end;
$$;
${userGrant(`${fn("restore_allocation")}(uuid, numeric, jsonb)`)}

-- Releases a document's open allocations: what they hold goes back to
-- available and their backorders close. Returns how many it released.
create or replace function ${fn("release_allocations")}(tenant ${ctx.idType}, document_type text, document_id text)
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
  ${guard(names.scope, names.reserve, "release_allocations.tenant")}
  for v_row in
    select x.${a("id")} as id, x.${a("tenant")} as tenant, x.${a("variant")} as variant, x.${a("location")} as location,
      x.${a("documentType")} as document_type, x.${a("documentId")} as document_id, x.${a("quantity")} as quantity, x.${a("allocated")} as allocated
    from ${allocations} x
    where x.${a("tenant")} = release_allocations.tenant and x.${a("documentType")} = release_allocations.document_type
      and x.${a("documentId")} = release_allocations.document_id and x.${a("status")} = 'open'
    order by x.${a("createdAt")}
    for update
  loop
    if v_row.allocated > 0 then
      ${reserve("v_row.variant", "v_row.location", "-v_row.allocated")}
    end if;
    update ${allocations} x set ${a("allocated")} = 0, ${a("status")} = 'released', ${a("updatedAt")} = now() where x.${a("id")} = v_row.id;
    ${event("allocation.released", "v_row")}
    if v_row.allocated > 0 then
      perform ${fn("fill_backorders")}(v_row.tenant, v_row.variant, v_row.location);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("release_allocations")}(${ctx.idType}, text, text)`)}

-- A document's allocations, oldest first.
create or replace function ${fn("list_allocations")}(tenant ${ctx.idType}, document_type text, document_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or ${names.scope.can("list_allocations.tenant", names.read)}) then
    ${fail("INVENTORY_FORBIDDEN", "not allowed to read this inventory")}
  end if;
  return coalesce((select jsonb_agg(${allocationJson(ctx, "x")} order by x.${a("createdAt")}, x.${a("id")})
    from ${allocations} x where x.${a("tenant")} = list_allocations.tenant
      and x.${a("documentType")} = list_allocations.document_type and x.${a("documentId")} = list_allocations.document_id), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_allocations")}(${ctx.idType}, text, text)`)}
`;
}
