import type { BlockSqlContext } from "../context.ts";
import type { ManufacturingSql } from "./manufacturing-sql.ts";

import { bookSource } from "../accounting-sources-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { fail, userGrant, writeExtraColumns } from "../shared.ts";
import { movementLots } from "./inventory-ledger.ts";
import { locationsOf, moveStock } from "./inventory-stock.ts";
import { variantOf } from "./manufacturing-boms.ts";
import { linked, manufacturingSql } from "./manufacturing-sql.ts";
import { asService } from "./orders-shared.ts";

/** The allocations' document type for a production order. */
export const PRODUCTION_DOCUMENT = "production_order";

/**
 * The JSON of a production order with its operations, components and
 * consumptions.
 */
export function orderDetail(q: ManufacturingSql, row: string): string {
  const { b, c, po, op, pc } = q;
  const a = (column: string): string => q.inventory.col("allocations", column);

  return `(${q.orderJson(row)} || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(${q.orderOperationJson("y")} order by y.${op("sequence")})
      from ${q.orderOperations} y where y.${op("order")} = ${row}.${po("id")}), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y.${c("id")}, 'variantId', y.${c("variant")},
        'quantity', ${q.fn("production_quantity")}(y.${c("variant")}, y.${c("quantity")} * ${row}.${po("quantity")} / x.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0))::text,
        'allocated', coalesce(al.${a("allocated")}, 0)::text, 'backordered', coalesce(al.${a("backordered")}, 0)::text,
        'consumed', coalesce((select sum(z.${pc("quantity")}) from ${q.consumptions} z
          where z.${pc("order")} = ${row}.${po("id")} and z.${pc("variant")} = y.${c("variant")}), 0)::text)
      order by y.${c("position")}, y.${c("id")})
      from ${q.boms} x join ${q.components} y on y.${c("bom")} = x.${b("id")}
      left join ${q.inventory.table("allocations")} al on al.${a("tenant")} = ${row}.${po("tenant")}
        and al.${a("documentType")} = '${PRODUCTION_DOCUMENT}' and al.${a("documentId")} = ${row}.${po("id")}::text
        and al.${a("line")} = y.${c("id")}::text and al.${a("status")} = 'open'
      where x.${b("id")} = ${row}.${po("bom")}), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z.${pc("id")}, 'variantId', z.${pc("variant")}, 'lotId', z.${pc("lot")},
        'serial', z.${pc("serial")}, 'quantity', z.${pc("quantity")}::text, 'cost', z.${pc("cost")}::text, 'currency', z.${pc("currency")},
        'movementId', z.${pc("movement")}, 'createdAt', z.${pc("createdAt")}) order by z.${pc("createdAt")}, z.${pc("id")})
      from ${q.consumptions} z where z.${pc("order")} = ${row}.${po("id")}), '[]'::jsonb)))`;
}

export function productionFunctions(ctx: BlockSqlContext): string {
  const q = manufacturingSql(ctx);
  const { fn, b, c, w, o, po, op, pc, ll } = q;
  const idType = ctx.idType;
  const inventory = q.inventory;
  const ledger = inventory.of("ledger");
  const loc = locationsOf(inventory);
  const it = (column: string): string => inventory.col("items", column);
  const a = (column: string): string => inventory.col("allocations", column);
  const s = (column: string): string => inventory.col("serials", column);
  const le = (column: string): string => ledger.col("entries", column);
  const la = (column: string): string => ledger.col("accounts", column);
  const inspections = linked(ctx, "inspections");
  const detail = (row: string): string => orderDetail(q, row);
  const reference = (row: string): string => `${row}.${po("id")}::text`;

  const load = (
    name: string,
    param: string,
  ): string => `select * into v_row from ${q.orders} x where x.${po("id")} = ${name}.${param} for update;
  if not found then
    ${q.orderMissing}
  end if;`;

  const releaseAllocations = (row: string): string =>
    asService(
      `perform ${inventory.fn("release_allocations")}(${row}.${po("tenant")}, '${PRODUCTION_DOCUMENT}', ${reference(row)});`,
    );

  const numberAssign = assignNumberSql(
    ctx,
    "production_order",
    "create_production_order.tenant",
    { seq: "v_seq", identifier: "v_number" },
    {
      table: q.orders,
      seq: po("sequence"),
      tenant: po("tenant"),
      prefix: "MO-",
    },
  );

  const schedule = inspections
    ? `if v_template is not null then
    ${asService(`v_inspection := (${inspections.fn("schedule_inspection")}(v_order.${po("tenant")}, jsonb_build_object('kind', v_template,
      'title', v_order.${po("number")} || ' ' || v_row.${op("title")}, 'plannedStart', current_date,
      'auditee', jsonb_build_object('type', ${q.orderSubject}, 'id', v_order.${po("id")}::text))) ->> 'id')::uuid;`)}
    update ${q.orderOperations} x set ${op("inspection")} = v_inspection where x.${op("id")} = v_row.${op("id")};
  end if;`
    : "";

  return `
-- Takes quantity of a component out of stock for a production order, from
-- the order's open allocation of the variant when it has one, and records
-- the consumption per lot (or serial) at its stock value. The caller checks
-- permissions and the order's status. Returns the stock movement.
create or replace function ${fn("production_consume")}(order_id uuid, variant uuid, quantity numeric, detail jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_order ${q.orders};
  v_allocation uuid;
  v_movement uuid;
  v_cost bigint;
  v_currency text;
  v_serials text[];
begin
  select * into v_order from ${q.orders} x where x.${po("id")} = production_consume.order_id;
  select x.${a("id")} into v_allocation from ${inventory.table("allocations")} x
  where x.${a("tenant")} = v_order.${po("tenant")} and x.${a("documentType")} = '${PRODUCTION_DOCUMENT}'
    and x.${a("documentId")} = v_order.${po("id")}::text and x.${a("variant")} = production_consume.variant
    and x.${a("status")} = 'open' and x.${a("quantity")} - x.${a("fulfilled")} >= production_consume.quantity
  order by x.${a("createdAt")}, x.${a("id")}
  limit 1;
  if v_allocation is not null then
    v_movement := (${inventory.fn("take_allocation")}(v_allocation, production_consume.quantity, 'consumption', production_consume.detail) ->> 'movementId')::uuid;
  else
    v_movement := ${moveStock(inventory, { tenant: `v_order.${po("tenant")}`, variant: "production_consume.variant", location: `v_order.${po("location")}`, quantity: "-production_consume.quantity", reason: "'consumption'", referenceType: `'${PRODUCTION_DOCUMENT}'`, referenceId: reference("v_order"), detail: "production_consume.detail" })};
  end if;
  select coalesce(-sum(e.${le("amount")}), 0), min(y.${la("unit")}) into v_cost, v_currency
  from ${ledger.table("entries")} e join ${ledger.table("accounts")} y on y.${la("id")} = e.${le("account")}
  where e.${le("transaction")} = v_movement and y.${la("kind")} = 'stock_value';
  if jsonb_typeof(production_consume.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(production_consume.detail -> 'serials'));
  end if;
  if coalesce(cardinality(v_serials), 0) > 0 then
    insert into ${q.consumptions} (${pc("tenant")}, ${pc("order")}, ${pc("variant")}, ${pc("lot")}, ${pc("serial")}, ${pc("quantity")}, ${pc("cost")}, ${pc("currency")}, ${pc("movement")}, ${pc("createdBy")})
    select v_order.${po("tenant")}, v_order.${po("id")}, production_consume.variant,
      (select z.${s("lot")} from ${inventory.table("serials")} z where z.${s("variant")} = production_consume.variant and z.${s("serial")} = e.serial),
      e.serial, 1, round(v_cost * e.n / cardinality(v_serials)) - round(v_cost * (e.n - 1) / cardinality(v_serials)), v_currency, v_movement, auth.uid()
    from unnest(v_serials) with ordinality e(serial, n);
  else
    insert into ${q.consumptions} (${pc("tenant")}, ${pc("order")}, ${pc("variant")}, ${pc("lot")}, ${pc("quantity")}, ${pc("cost")}, ${pc("currency")}, ${pc("movement")}, ${pc("createdBy")})
    select v_order.${po("tenant")}, v_order.${po("id")}, production_consume.variant, g.lot, g.quantity,
      round(v_cost * g.upto / production_consume.quantity) - round(v_cost * (g.upto - g.quantity) / production_consume.quantity),
      v_currency, v_movement, auth.uid()
    from (select nullif(p ->> 'lotId', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity,
        sum((p ->> 'quantity')::numeric) over (order by p ->> 'lotId' nulls last) as upto
      from jsonb_array_elements(coalesce(${movementLots(inventory, "v_movement")}, '[]'::jsonb)) p
      where (p ->> 'quantity')::numeric > 0) g;
  end if;
  return v_movement;
end;
$$;
revoke execute on function ${fn("production_consume")}(uuid, uuid, numeric, jsonb) from public, anon, authenticated;

-- Creates a draft production order: input is { variantId, quantity,
-- locationId, dueOn, bomId, note, fields }. It pins the variant's active
-- bill of materials (or bomId, which must be active) and takes its number
-- from the numbering block. locationId defaults to the first active location.
create or replace function ${fn("create_production_order")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orders};
  v_variant uuid;
  v_quantity numeric;
  v_location uuid;
  v_bom uuid;
  v_seq bigint;
  v_number text;
begin
  if not ${q.allowed("create_production_order.tenant", q.write)} then
    ${q.forbidden("not allowed to create production orders")}
  end if;
  if jsonb_typeof(create_production_order.input) is distinct from 'object' then
    ${q.orderInvalid("input must be an object")}
  end if;
  v_variant := nullif(create_production_order.input ->> 'variantId', '')::uuid;
  v_quantity := nullif(create_production_order.input ->> 'quantity', '')::numeric;
  if v_variant is null or not ${variantOf(q, "create_production_order.tenant", "v_variant")} then
    ${q.orderInvalid("the variant isn't a variant of this organization")}
  end if;
  if v_quantity is null or v_quantity <= 0 then
    ${q.orderInvalid("the quantity must be more than zero")}
  end if;
  v_location := nullif(create_production_order.input ->> 'locationId', '')::uuid;
  if v_location is null then
    select y.${loc.col("id")} into v_location from ${loc.table} y
    where y.${loc.col("tenant")} = create_production_order.tenant and ${loc.active("y")}
    order by y.${loc.col("code")}
    limit 1;
  end if;
  if v_location is null or not exists (select 1 from ${loc.table} y where y.${loc.col("id")} = v_location
    and y.${loc.col("tenant")} = create_production_order.tenant and ${loc.active("y")}) then
    ${q.orderInvalid("the location isn't an active location of this organization")}
  end if;
  select x.${b("id")} into v_bom from ${q.boms} x
  where x.${b("variant")} = v_variant and x.${b("status")} = 'active'
    and (nullif(create_production_order.input ->> 'bomId', '') is null or x.${b("id")} = (create_production_order.input ->> 'bomId')::uuid);
  if v_bom is null then
    ${fail("BOM_NOT_ACTIVE", "the variant has no active bill of materials", "55000")}
  end if;
  ${numberAssign}
  insert into ${q.orders} (${po("tenant")}, ${po("number")}, ${po("sequence")}, ${po("variant")}, ${po("bom")}, ${po("quantity")}, ${po("location")}, ${po("dueOn")}, ${po("note")}, ${po("createdBy")})
  values (create_production_order.tenant, v_number, v_seq, v_variant, v_bom, v_quantity, v_location,
    nullif(create_production_order.input ->> 'dueOn', '')::date, nullif(trim(create_production_order.input ->> 'note'), ''), auth.uid())
  returning * into v_row;${writeExtraColumns(q.orders, q.extras, "coalesce(create_production_order.input -> 'fields', '{}'::jsonb)", `x.${po("id")} = v_row.${po("id")}`, "v_row")}
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("create_production_order")}(${idType}, jsonb)`)}

-- Releases a draft production order to the floor: it copies the bill of
-- materials' operations with their planned minutes and allocates each
-- component's quantity (planned scrap included) at the order's location.
-- Refuses with PRODUCTION_ORDER_SHORTAGE when a component would go on
-- backorder, unless allow_shortage is true.
create or replace function ${fn("release_production_order")}(order_id uuid, allow_shortage boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orders};
  v_bom ${q.boms};
  v_component record;
  v_allocation jsonb;
  v_shortages jsonb := '[]'::jsonb;
  v_claims text;
begin
  ${load("release_production_order", "order_id")}
  if not ${q.allowed(`v_row.${po("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to release production orders")}
  end if;
  if v_row.${po("status")} <> 'draft' then
    ${q.statusInvalid("v_row", "released")}
  end if;
  ${ctx.hook("before_production_order_release", [["uuid", `v_row.${po("id")}`]])}
  select * into v_bom from ${q.boms} x where x.${b("id")} = v_row.${po("bom")};
  insert into ${q.orderOperations} (${op("tenant")}, ${op("order")}, ${op("operation")}, ${op("sequence")}, ${op("workCenter")}, ${op("title")}, ${op("plannedMinutes")})
  select v_row.${po("tenant")}, v_row.${po("id")}, y.${o("id")}, y.${o("sequence")}, y.${o("workCenter")}, y.${o("title")},
    round(y.${o("setupMinutes")} + y.${o("runMinutes")} * v_row.${po("quantity")}, 2)
  from ${q.operations} y where y.${o("bom")} = v_bom.${b("id")};
  for v_component in
    select y.${c("id")} as id, y.${c("variant")} as variant,
      ${fn("production_quantity")}(y.${c("variant")}, y.${c("quantity")} * v_row.${po("quantity")} / v_bom.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0)) as quantity
    from ${q.components} y where y.${c("bom")} = v_bom.${b("id")}
    order by y.${c("position")}, y.${c("id")}
  loop
    ${asService(`v_allocation := ${inventory.fn("allocate_stock")}(v_row.${po("tenant")}, v_component.variant, v_row.${po("location")}, v_component.quantity,
      '${PRODUCTION_DOCUMENT}', ${reference("v_row")}, v_component.id::text, true);`)}
    if (v_allocation ->> 'backordered')::numeric > 0 then
      v_shortages := v_shortages || jsonb_build_array(jsonb_build_object('variantId', v_component.variant,
        'quantity', v_component.quantity::text, 'backordered', v_allocation ->> 'backordered'));
    end if;
  end loop;
  if jsonb_array_length(v_shortages) > 0 and not coalesce(release_production_order.allow_shortage, false) then
    raise exception 'not enough stock for the production order''s components' using errcode = '23514',
      hint = 'PRODUCTION_ORDER_SHORTAGE', detail = jsonb_build_object('shortages', v_shortages)::text;
  end if;
  update ${q.orders} x set ${po("status")} = 'released', ${po("releasedAt")} = now(), ${po("updatedAt")} = now()
  where x.${po("id")} = v_row.${po("id")}
  returning * into v_row;
  ${q.recordOrder("production_order.released", "v_row", "production order released")}
  ${ctx.hook("after_production_order_release", [["uuid", `v_row.${po("id")}`]])}
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("release_production_order")}(uuid, boolean)`)}

-- Starts an operation of a released production order; the order moves to
-- in progress. An operation with an inspection template schedules an
-- inspection of that kind with the order as its auditee.
create or replace function ${fn("start_production_operation")}(operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orderOperations};
  v_order ${q.orders};
  v_template text;
  v_inspection uuid;
  v_claims text;
begin
  select * into v_row from ${q.orderOperations} x where x.${op("id")} = start_production_operation.operation_id for update;
  if not found then
    ${q.operationMissing}
  end if;
  select * into v_order from ${q.orders} x where x.${po("id")} = v_row.${op("order")} for update;
  if not ${q.allowed(`v_order.${po("tenant")}`, q.produce)} then
    ${q.forbidden("not allowed to run production operations")}
  end if;
  if v_order.${po("status")} not in ('released', 'in_progress') then
    ${q.statusInvalid("v_order", "in_progress")}
  end if;
  if v_row.${op("status")} <> 'pending' then
    ${q.orderInvalid("the operation has already started")}
  end if;
  update ${q.orderOperations} x set ${op("status")} = 'in_progress', ${op("startedAt")} = now(), ${op("operator")} = auth.uid()
  where x.${op("id")} = v_row.${op("id")}
  returning * into v_row;
  if v_order.${po("status")} = 'released' then
    update ${q.orders} x set ${po("status")} = 'in_progress', ${po("startedAt")} = now(), ${po("updatedAt")} = now()
    where x.${po("id")} = v_order.${po("id")}
    returning * into v_order;
  end if;
  select y.${o("inspectionTemplate")} into v_template from ${q.operations} y where y.${o("id")} = v_row.${op("operation")};
  ${schedule}
  return ${detail("v_order")};
end;
$$;
${userGrant(`${fn("start_production_operation")}(uuid)`)}

-- Finishes a started operation. minutes is the time worked; null takes the
-- time since it started.
create or replace function ${fn("finish_production_operation")}(operation_id uuid, minutes numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orderOperations};
  v_order ${q.orders};
begin
  select * into v_row from ${q.orderOperations} x where x.${op("id")} = finish_production_operation.operation_id for update;
  if not found then
    ${q.operationMissing}
  end if;
  select * into v_order from ${q.orders} x where x.${po("id")} = v_row.${op("order")} for update;
  if not ${q.allowed(`v_order.${po("tenant")}`, q.produce)} then
    ${q.forbidden("not allowed to run production operations")}
  end if;
  if v_row.${op("status")} <> 'in_progress' then
    ${q.orderInvalid("only a started operation finishes")}
  end if;
  if finish_production_operation.minutes is not null and finish_production_operation.minutes < 0 then
    ${q.orderInvalid("minutes can't be negative")}
  end if;
  update ${q.orderOperations} x set ${op("status")} = 'done', ${op("finishedAt")} = now(),
    ${op("minutes")} = round(coalesce(finish_production_operation.minutes, extract(epoch from now() - x.${op("startedAt")}) / 60), 2)
  where x.${op("id")} = v_row.${op("id")};
  return ${detail("v_order")};
end;
$$;
${userGrant(`${fn("finish_production_operation")}(uuid, numeric)`)}

-- Records quantity of a component taken for a released production order.
-- detail picks the bin, lot or serial numbers, as for move_stock; without
-- one, stock leaves first-expiry-first-out.
create or replace function ${fn("record_production_consumption")}(order_id uuid, variant uuid, quantity numeric, detail jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orders};
begin
  ${load("record_production_consumption", "order_id")}
  if not ${q.allowed(`v_row.${po("tenant")}`, q.produce)} then
    ${q.forbidden("not allowed to record production consumption")}
  end if;
  if v_row.${po("status")} not in ('released', 'in_progress') then
    ${q.statusInvalid("v_row", "in_progress")}
  end if;
  if record_production_consumption.variant is null or not ${variantOf(q, `v_row.${po("tenant")}`, "record_production_consumption.variant")} then
    ${q.orderInvalid("the variant isn't a variant of this organization")}
  end if;
  if record_production_consumption.quantity is null or record_production_consumption.quantity <= 0 then
    ${q.orderInvalid("the quantity must be more than zero")}
  end if;
  perform ${fn("production_consume")}(v_row.${po("id")}, record_production_consumption.variant, record_production_consumption.quantity, record_production_consumption.detail);
  update ${q.orders} x set ${po("status")} = 'in_progress', ${po("startedAt")} = coalesce(x.${po("startedAt")}, now()), ${po("updatedAt")} = now()
  where x.${po("id")} = v_row.${po("id")}
  returning * into v_row;
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("record_production_consumption")}(uuid, uuid, numeric, jsonb)`)}

-- Completes a production order: produced goes into stock at the order's
-- location and scrap is recorded. Components with nothing recorded are
-- backflushed for produced plus scrap, the rest of the allocations is
-- released, and open operations finish at their planned minutes. The output
-- is valued at the consumed components' stock value plus the work centers'
-- labor. lot is { code, expiresOn } or { lotId }; a lot-tracked variant
-- without one gets a lot named after the order. The output lot links to
-- every lot the order consumed.
create or replace function ${fn("complete_production_order")}(order_id uuid, produced numeric, scrap numeric default 0, lot jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orders};
  v_bom ${q.boms};
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
  ${load("complete_production_order", "order_id")}
  if not ${q.allowed(`v_row.${po("tenant")}`, q.produce)} then
    ${q.forbidden("not allowed to complete production orders")}
  end if;
  if v_row.${po("status")} not in ('released', 'in_progress') then
    ${q.statusInvalid("v_row", "done")}
  end if;
  if complete_production_order.produced is null or complete_production_order.produced <= 0 or v_scrap < 0 then
    ${q.orderInvalid("produced must be more than zero and scrap zero or more")}
  end if;
  if complete_production_order.lot is not null and jsonb_typeof(complete_production_order.lot) <> 'object' then
    ${q.orderInvalid("lot must be an object")}
  end if;
  ${ctx.hook("before_production_order_complete", [["uuid", `v_row.${po("id")}`]])}
  select * into v_bom from ${q.boms} x where x.${b("id")} = v_row.${po("bom")};
  for v_component in
    select y.${c("variant")} as variant,
      ${fn("production_quantity")}(y.${c("variant")}, y.${c("quantity")} * (complete_production_order.produced + v_scrap) / v_bom.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0)) as quantity
    from ${q.components} y where y.${c("bom")} = v_bom.${b("id")}
      and not exists (select 1 from ${q.consumptions} z where z.${pc("order")} = v_row.${po("id")} and z.${pc("variant")} = y.${c("variant")})
    order by y.${c("position")}, y.${c("id")}
  loop
    perform ${fn("production_consume")}(v_row.${po("id")}, v_component.variant, v_component.quantity, null);
  end loop;
  ${releaseAllocations("v_row")}
  update ${q.orderOperations} x set ${op("status")} = 'done', ${op("startedAt")} = coalesce(x.${op("startedAt")}, now()),
    ${op("finishedAt")} = now(), ${op("minutes")} = coalesce(x.${op("minutes")}, x.${op("plannedMinutes")})
  where x.${op("order")} = v_row.${po("id")} and x.${op("status")} <> 'done';

  select x.${it("tracking")}, x.${it("currency")} into v_tracking, v_item_currency
  from ${inventory.table("items")} x where x.${it("variant")} = v_row.${po("variant")};
  v_currency := coalesce(v_item_currency,
    (select min(z.${pc("currency")}) from ${q.consumptions} z where z.${pc("order")} = v_row.${po("id")}),
    (select min(y.${w("currency")}) from ${q.orderOperations} x join ${q.workCenters} y on y.${w("id")} = x.${op("workCenter")}
      where x.${op("order")} = v_row.${po("id")}));
  select coalesce(sum(z.${pc("cost")}), 0) into v_material from ${q.consumptions} z
  where z.${pc("order")} = v_row.${po("id")} and z.${pc("currency")} is not distinct from v_currency;
  select coalesce(sum(round(x.${op("minutes")} * y.${w("costRate")} / 60.0)), 0)::bigint into v_labor
  from ${q.orderOperations} x join ${q.workCenters} y on y.${w("id")} = x.${op("workCenter")}
  where x.${op("order")} = v_row.${po("id")} and y.${w("currency")} = v_currency;

  v_lot := nullif(complete_production_order.lot ->> 'lotId', '')::uuid;
  if v_lot is null and (nullif(complete_production_order.lot ->> 'code', '') is not null or v_tracking = 'lot') then
    v_lot := ${inventory.fn("stock_lot_for")}(v_row.${po("tenant")}, v_row.${po("variant")},
      coalesce(nullif(complete_production_order.lot ->> 'code', ''), v_row.${po("number")}),
      nullif(complete_production_order.lot ->> 'expiresOn', '')::date);
  end if;
  perform ${moveStock(inventory, {
    tenant: `v_row.${po("tenant")}`,
    variant: `v_row.${po("variant")}`,
    location: `v_row.${po("location")}`,
    quantity: "complete_production_order.produced",
    reason: "'production'",
    referenceType: `'${PRODUCTION_DOCUMENT}'`,
    referenceId: reference("v_row"),
    detail: `jsonb_strip_nulls(jsonb_build_object('lotId', v_lot, 'serials', complete_production_order.lot -> 'serials',
      'unitCost', round((v_material + v_labor)::numeric / complete_production_order.produced, 6)::text, 'currency', v_item_currency))`,
  })};
  if v_lot is not null then
    insert into ${q.lotLinks} (${ll("tenant")}, ${ll("parent")}, ${ll("child")}, ${ll("order")}, ${ll("quantity")})
    select v_row.${po("tenant")}, v_lot, z.${pc("lot")}, v_row.${po("id")}, sum(z.${pc("quantity")})
    from ${q.consumptions} z where z.${pc("order")} = v_row.${po("id")} and z.${pc("lot")} is not null and z.${pc("lot")} <> v_lot
    group by z.${pc("lot")};
  end if;
  update ${q.orders} x set ${po("status")} = 'done', ${po("produced")} = complete_production_order.produced, ${po("scrap")} = v_scrap,
    ${po("outputLot")} = v_lot, ${po("materialCost")} = v_material, ${po("laborCost")} = v_labor, ${po("currency")} = v_currency,
    ${po("startedAt")} = coalesce(x.${po("startedAt")}, now()), ${po("completedAt")} = now(), ${po("updatedAt")} = now()
  where x.${po("id")} = v_row.${po("id")}
  returning * into v_row;
  if v_labor > 0 then
    ${bookSource(ctx, "production_order", `v_row.${po("id")}`) || "null;"}
  end if;
  ${q.recordOrder("production_order.completed", "v_row", "production order completed", `, 'producedQuantity', v_row.${po("produced")}::text, 'scrapQuantity', v_row.${po("scrap")}::text, 'outputLotId', v_row.${po("outputLot")}`)}
  ${ctx.hook("after_production_order_complete", [["uuid", `v_row.${po("id")}`]])}
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("complete_production_order")}(uuid, numeric, numeric, jsonb)`)}

-- Cancels a production order that isn't done: its allocations are released
-- and the components it consumed go back into stock, the same lots and
-- serial numbers at the value they left at.
create or replace function ${fn("cancel_production_order")}(order_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.orders};
  v_consumption record;
  v_claims text;
begin
  ${load("cancel_production_order", "order_id")}
  if not ${q.allowed(`v_row.${po("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to cancel production orders")}
  end if;
  if v_row.${po("status")} not in ('draft', 'released', 'in_progress') then
    ${q.statusInvalid("v_row", "canceled")}
  end if;
  if cancel_production_order.reason is not null and length(cancel_production_order.reason) > 1000 then
    ${q.orderInvalid("the reason is at most 1000 characters")}
  end if;
  ${releaseAllocations("v_row")}
  for v_consumption in
    select z.${pc("variant")} as variant, z.${pc("lot")} as lot, z.${pc("currency")} as currency,
      array_agg(z.${pc("serial")}) filter (where z.${pc("serial")} is not null) as serials,
      sum(z.${pc("quantity")}) as quantity, sum(z.${pc("cost")}) as cost
    from ${q.consumptions} z where z.${pc("order")} = v_row.${po("id")}
    group by z.${pc("variant")}, z.${pc("lot")}, z.${pc("currency")}
  loop
    perform ${moveStock(inventory, {
      tenant: `v_row.${po("tenant")}`,
      variant: "v_consumption.variant",
      location: `v_row.${po("location")}`,
      quantity: "v_consumption.quantity",
      reason: "'consumption'",
      referenceType: `'${PRODUCTION_DOCUMENT}'`,
      referenceId: reference("v_row"),
      note: "'production order canceled'",
      detail: `jsonb_strip_nulls(jsonb_build_object('lotId', v_consumption.lot, 'serials', to_jsonb(v_consumption.serials),
      'unitCost', case when v_consumption.currency is null then null else round(v_consumption.cost::numeric / v_consumption.quantity, 6)::text end,
      'currency', v_consumption.currency))`,
    })};
  end loop;
  update ${q.orders} x set ${po("status")} = 'canceled', ${po("canceledAt")} = now(), ${po("updatedAt")} = now()
  where x.${po("id")} = v_row.${po("id")}
  returning * into v_row;
  ${q.recordOrder("production_order.canceled", "v_row", "production order canceled", ", 'reason', cancel_production_order.reason")}
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("cancel_production_order")}(uuid, text)`)}

-- A production order with its operations, components and consumptions.
create or replace function ${fn("get_production_order")}(order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${q.orders};
begin
  select * into v_row from ${q.orders} x where x.${po("id")} = get_production_order.order_id;
  if not found or not ${q.allowed(`v_row.${po("tenant")}`, q.read)} then
    ${q.orderMissing}
  end if;
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("get_production_order")}(uuid)`)}

-- The organization's production orders, due first: filter is { status,
-- variantId, limit } (limit 1 to 500, default 100).
create or replace function ${fn("list_production_orders")}(tenant ${idType}, filter jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_production_orders.tenant", q.read)} then
    ${q.forbidden("not allowed to read production orders")}
  end if;
  return coalesce((select jsonb_agg(${q.orderJson("x")} order by x.${po("dueOn")} nulls last, x.${po("sequence")} desc)
    from (select * from ${q.orders} y where y.${po("tenant")} = list_production_orders.tenant
      and (nullif(list_production_orders.filter ->> 'status', '') is null or y.${po("status")} = list_production_orders.filter ->> 'status')
      and (nullif(list_production_orders.filter ->> 'variantId', '') is null or y.${po("variant")} = (list_production_orders.filter ->> 'variantId')::uuid)
      order by y.${po("dueOn")} nulls last, y.${po("sequence")} desc
      limit least(greatest(coalesce(nullif(list_production_orders.filter ->> 'limit', '')::integer, 100), 1), 500)) x), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_production_orders")}(${idType}, jsonb)`)}
`;
}
