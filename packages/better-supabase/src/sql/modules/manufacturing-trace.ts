import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { locationsOf } from "./inventory-stock.ts";
import { manufacturingSql } from "./manufacturing-sql.ts";
import { BOM_MAX_DEPTH, PURCHASE_SUGGESTIONS } from "./manufacturing-values.ts";
import { asService } from "./orders-shared.ts";

const DEPTH = String(BOM_MAX_DEPTH);

/** `options.purchaseSuggestions`, `order` by default. */
function purchaseSuggestions(
  ctx: BlockSqlContext,
): (typeof PURCHASE_SUGGESTIONS)[number] {
  const value = ctx.option("purchaseSuggestions") ?? "order";

  if (!PURCHASE_SUGGESTIONS.some((known) => known === value)) {
    throw new TypeError(
      `blocks.manufacturing.options.purchaseSuggestions must be one of ${PURCHASE_SUGGESTIONS.join(", ")}`,
    );
  }

  return value === "requisition" ? "requisition" : "order";
}

export function traceFunctions(ctx: BlockSqlContext): string {
  const q = manufacturingSql(ctx);
  const { fn, b, c, po, pc, ll } = q;
  const idType = ctx.idType;
  const inventory = q.inventory;
  const ledger = inventory.of("ledger");
  const loc = locationsOf(inventory);
  const lt = (column: string): string => inventory.col("lots", column);
  const lv = (column: string): string => inventory.col("levels", column);
  const k = (column: string): string => inventory.col("buckets", column);
  const it = (column: string): string => inventory.col("items", column);
  const a = (column: string): string => inventory.col("allocations", column);
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const la = (column: string): string => ledger.col("accounts", column);
  const lots = inventory.table("lots");

  const purchasing =
    inventory.hasTable("purchaseOrders") &&
    inventory.hasTable("purchaseOrderLines");

  const requisitions = purchaseSuggestions(ctx) === "requisition";

  if (
    requisitions &&
    !(
      purchasing &&
      inventory.hasTable("requisitions") &&
      inventory.hasTable("requisitionLines")
    )
  ) {
    throw new TypeError(
      'blocks.manufacturing.options.purchaseSuggestions: "requisition" needs the inventory purchase requisition tables',
    );
  }

  const createPurchase = requisitions
    ? `v_purchase := ${inventory.fn("request_purchase")}(create_from_requirements.tenant, v_group.location, v_group.lines,
      v_group.supplier_type, v_group.supplier_id, v_group.currency, 'From material requirements');`
    : `v_purchase := ${inventory.fn("save_purchase_order")}(create_from_requirements.tenant, null, v_group.location, v_group.supplier_type,
      v_group.supplier_id, v_group.currency, null, v_group.lines, 'From material requirements');`;

  const lotJson = (alias: string): string =>
    `jsonb_build_object('lotId', ${alias}.${lt("id")}, 'code', ${alias}.${lt("code")}, 'variantId', ${alias}.${lt("variant")}, 'expiresOn', ${alias}.${lt("expiresOn")})`;

  const loadLot = (
    name: string,
  ): string => `select x.${lt("tenant")} into v_tenant from ${lots} x where x.${lt("id")} = ${name}.lot_id;
  if v_tenant is null or not ${q.allowed("v_tenant", q.read)} then
    ${fail("INVENTORY_LOT_NOT_FOUND", "no such lot", "P0002")}
  end if;`;

  const purchase = purchasing
    ? `for v_group in
    select coalesce(nullif(e ->> 'locationId', '')::uuid, v_default_location) as location,
      nullif(e ->> 'supplierType', '') as supplier_type, nullif(e ->> 'supplierId', '') as supplier_id,
      upper(coalesce(nullif(e ->> 'currency', ''), (select y.${it("currency")} from ${inventory.table("items")} y where y.${it("variant")} = (e ->> 'variantId')::uuid))) as currency,
      jsonb_agg(jsonb_build_object('variantId', e ->> 'variantId', 'quantity', e ->> 'quantity',
        'unitCost', coalesce(nullif(e ->> 'unitCost', ''), (select round(coalesce(y.${it("averageCost")}, 0))::bigint::text
          from ${inventory.table("items")} y where y.${it("variant")} = (e ->> 'variantId')::uuid), '0'))) as lines
    from jsonb_array_elements(create_from_requirements.items) e
    where e ->> 'action' = 'purchase'
    group by 1, 2, 3, 4
  loop
    if v_group.currency is null then
      ${q.orderInvalid("a purchase suggestion needs a currency: set one on the item or the variant's costing")}
    end if;
    ${asService(createPurchase)}
    v_purchases := v_purchases || jsonb_build_array(v_purchase);
  end loop;`
    : `if exists (select 1 from jsonb_array_elements(create_from_requirements.items) e where e ->> 'action' = 'purchase') then
    ${q.orderInvalid("purchase suggestions need the inventory purchase order tables")}
  end if;`;

  return `
-- The lots a lot was made from (direction down) or the lots made from it
-- (direction up), at every level: { lotId, direction, lots: [{ level,
-- lotId, code, variantId, expiresOn, fromLotId, orderId, quantity }] }.
create or replace function ${fn("lot_genealogy")}(lot_id uuid, direction text default 'down')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
begin
  ${loadLot("lot_genealogy")}
  if lot_genealogy.direction is null or lot_genealogy.direction not in ('up', 'down') then
    ${q.orderInvalid("direction is up or down")}
  end if;
  return jsonb_build_object('lotId', lot_genealogy.lot_id, 'direction', lot_genealogy.direction,
    'lots', coalesce((with recursive tree(lot, from_lot, order_id, quantity, level, path) as (
      select case when lot_genealogy.direction = 'down' then y.${ll("child")} else y.${ll("parent")} end, lot_genealogy.lot_id,
        y.${ll("order")}, y.${ll("quantity")}, 1, array[lot_genealogy.lot_id]
      from ${q.lotLinks} y
      where (lot_genealogy.direction = 'down' and y.${ll("parent")} = lot_genealogy.lot_id)
        or (lot_genealogy.direction = 'up' and y.${ll("child")} = lot_genealogy.lot_id)
      union all
      select case when lot_genealogy.direction = 'down' then y.${ll("child")} else y.${ll("parent")} end, tree.lot,
        y.${ll("order")}, y.${ll("quantity")}, tree.level + 1, tree.path || tree.lot
      from tree join ${q.lotLinks} y
        on (lot_genealogy.direction = 'down' and y.${ll("parent")} = tree.lot)
        or (lot_genealogy.direction = 'up' and y.${ll("child")} = tree.lot)
      where tree.level < ${DEPTH} and not (tree.lot = any (tree.path))
    )
    select jsonb_agg(${lotJson("l")} || jsonb_build_object('level', t.level, 'fromLotId', t.from_lot, 'orderId', t.order_id,
      'quantity', t.quantity::text) order by t.level, l.${lt("code")})
    from tree t join ${lots} l on l.${lt("id")} = t.lot), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("lot_genealogy")}(uuid, text)`)}

-- What a recall of a lot reaches: the lot and every lot made from it, the
-- stock of those lots still on hand, the documents they left stock for (a
-- sale's order or shipment) and the production orders that consumed them.
create or replace function ${fn("lot_recall")}(lot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
  v_lots uuid[];
begin
  ${loadLot("lot_recall")}
  with recursive up(lot, level, path) as (
    select lot_recall.lot_id, 0, array[lot_recall.lot_id]
    union all
    select y.${ll("parent")}, up.level + 1, up.path || y.${ll("parent")}
    from up join ${q.lotLinks} y on y.${ll("child")} = up.lot
    where up.level < ${DEPTH} and not (y.${ll("parent")} = any (up.path))
  )
  select array_agg(distinct up.lot) into v_lots from up;
  return jsonb_build_object('lotId', lot_recall.lot_id,
    'lots', coalesce((select jsonb_agg(${lotJson("l")} order by l.${lt("code")}) from ${lots} l where l.${lt("id")} = any (v_lots)), '[]'::jsonb),
    'stock', coalesce((select jsonb_agg(jsonb_build_object('lotId', y.${k("lot")}, 'variantId', y.${k("variant")}, 'locationId', y.${k("location")},
        'binId', y.${k("bin")}, 'onHand', y.${k("onHand")}::text) order by y.${k("lot")}, y.${k("location")})
      from ${inventory.table("buckets")} y where y.${k("lot")} = any (v_lots) and y.${k("onHand")} > 0), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('referenceType', d.reference_type, 'referenceId', d.reference_id,
        'lotId', d.lot, 'variantId', d.variant, 'quantity', d.quantity::text, 'at', d.at) order by d.at, d.reference_id)
      from (select t.${tx("referenceType")} as reference_type, t.${tx("referenceId")} as reference_id,
          (y.${la("metadata")} ->> 'lotId')::uuid as lot, (y.${la("metadata")} ->> 'variantId')::uuid as variant,
          sum(-e.${le("amount")} / power(10::numeric, y.${la("scale")})) as quantity, min(t.${tx("effectiveAt")}) as at
        from ${ledger.table("transactions")} t
        join ${ledger.table("entries")} e on e.${le("transaction")} = t.${tx("id")}
        join ${ledger.table("accounts")} y on y.${la("id")} = e.${le("account")} and y.${la("kind")} = 'stock'
        where t.${tx("tenant")} = v_tenant and t.${tx("kind")} in ('stock.sale', 'stock.transfer_out') and t.${tx("referenceId")} is not null
          and (y.${la("metadata")} ->> 'lotId')::uuid = any (v_lots)
        group by 1, 2, 3, 4
        having sum(-e.${le("amount")}) > 0) d), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('orderId', o.${po("id")}, 'number', o.${po("number")}, 'status', o.${po("status")},
        'variantId', o.${po("variant")}, 'outputLotId', o.${po("outputLot")}) order by o.${po("number")})
      from ${q.orders} o where o.${po("status")} <> 'canceled'
        and exists (select 1 from ${q.consumptions} z where z.${pc("order")} = o.${po("id")} and z.${pc("lot")} = any (v_lots))), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("lot_recall")}(uuid)`)}

-- One netting pass of material requirements: per variant the demand
-- (backorders, components of draft production orders due within the
-- horizon, and extra, a { variantId: quantity } map), the supply (available,
-- incoming, production orders not done) and the reorder point. A variant
-- whose projected stock ends below its reorder point (or zero) gets a
-- suggestion: produce when it has an active bill of materials, else
-- purchase.
create or replace function ${fn("requirements_pass")}(tenant ${idType}, horizon_days integer, extra jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with horizon as (select current_date + greatest(coalesce(requirements_pass.horizon_days, 30), 0) as until),
  levels as (
    select x.${lv("variant")} as variant, sum(x.${lv("available")}) as available, sum(x.${lv("incoming")}) as incoming,
      sum(x.${lv("reorderPoint")}) as reorder_point
    from ${inventory.table("levels")} x where x.${lv("tenant")} = requirements_pass.tenant
    group by 1
  ),
  backorders as (
    select x.${a("variant")} as variant, sum(x.${a("backordered")}) as quantity
    from ${inventory.table("allocations")} x
    where x.${a("tenant")} = requirements_pass.tenant and x.${a("status")} = 'open' and x.${a("backordered")} > 0
    group by 1
  ),
  draft_needs as (
    select y.${c("variant")} as variant,
      sum(${fn("production_quantity")}(y.${c("variant")}, y.${c("quantity")} * o.${po("quantity")} / x.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0))) as quantity
    from ${q.orders} o
    join ${q.boms} x on x.${b("id")} = o.${po("bom")}
    join ${q.components} y on y.${c("bom")} = x.${b("id")}
    where o.${po("tenant")} = requirements_pass.tenant and o.${po("status")} = 'draft'
      and (o.${po("dueOn")} is null or o.${po("dueOn")} <= (select until from horizon))
    group by 1
  ),
  planned as (
    select o.${po("variant")} as variant, sum(o.${po("quantity")} - o.${po("produced")}) as quantity
    from ${q.orders} o
    where o.${po("tenant")} = requirements_pass.tenant and o.${po("status")} in ('draft', 'released', 'in_progress')
      and (o.${po("dueOn")} is null or o.${po("dueOn")} <= (select until from horizon))
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
      (select x.${b("id")} from ${q.boms} x where x.${b("variant")} = v.variant and x.${b("status")} = 'active') as bom
    from variants v
    left join levels l on l.variant = v.variant
    left join backorders bo on bo.variant = v.variant
    left join draft_needs d on d.variant = v.variant
    left join planned p on p.variant = v.variant
    left join extras e on e.variant = v.variant
  )
  select coalesce(jsonb_agg(jsonb_build_object('variantId', n.variant, 'action', case when n.bom is null then 'purchase' else 'produce' end,
      'bomId', n.bom, 'quantity', ${fn("production_quantity")}(n.variant, coalesce(n.reorder_point, 0) - (n.available + n.incoming + n.planned - n.demand))::text,
      'available', n.available::text, 'incoming', n.incoming::text, 'planned', n.planned::text, 'demand', n.demand::text,
      'reorderPoint', n.reorder_point::text) order by n.variant), '[]'::jsonb)
  from net n
  where coalesce(n.reorder_point, 0) - (n.available + n.incoming + n.planned - n.demand) > 0;
$$;
revoke execute on function ${fn("requirements_pass")}(${idType}, integer, jsonb) from public, anon, authenticated;

-- What the organization has to produce or buy to cover its demand within
-- horizon_days: { organizationId, horizonDays, items: [{ variantId, action,
-- bomId, quantity, available, incoming, planned, demand, reorderPoint }] }.
-- A produce suggestion adds its components' quantities to their demand, so
-- every level of the bills of materials is netted.
create or replace function ${fn("material_requirements")}(tenant ${idType}, horizon_days integer default 30)
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
  if not ${q.allowed("material_requirements.tenant", q.read)} then
    ${q.forbidden("not allowed to read material requirements")}
  end if;
  if material_requirements.horizon_days is not null and material_requirements.horizon_days not between 0 and 3650 then
    ${q.orderInvalid("horizon_days is 0 to 3650")}
  end if;
  loop
    v_items := ${fn("requirements_pass")}(material_requirements.tenant, material_requirements.horizon_days, v_extra);
    select coalesce(jsonb_object_agg(g.variant, g.quantity::text), '{}'::jsonb) into v_next
    from (select y.${c("variant")}::text as variant,
        sum(y.${c("quantity")} * (i ->> 'quantity')::numeric / x.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0)) as quantity
      from jsonb_array_elements(v_items) i
      join ${q.boms} x on x.${b("id")} = (i ->> 'bomId')::uuid
      join ${q.components} y on y.${c("bom")} = x.${b("id")}
      where i ->> 'action' = 'produce'
      group by 1) g;
    v_pass := v_pass + 1;
    exit when v_next = v_extra or v_pass > ${DEPTH};
    v_extra := v_next;
  end loop;
  return jsonb_build_object('organizationId', material_requirements.tenant,
    'horizonDays', coalesce(material_requirements.horizon_days, 30), 'items', v_items);
end;
$$;
${userGrant(`${fn("material_requirements")}(${idType}, integer)`)}

-- Turns material requirement suggestions into documents: items is [{
-- variantId, action, quantity, dueOn, locationId }]; a produce item becomes
-- a draft production order, purchase items become draft purchase orders of
-- the inventory block${requisitions ? "'s purchase requisitions (options.purchaseSuggestions)" : ""}, one per location, supplier ({ supplierType,
-- supplierId }) and currency, at unitCost or the variant's average cost.
-- Returns { productionOrders, purchaseOrders, purchaseRequisitions }.
create or replace function ${fn("create_from_requirements")}(tenant ${idType}, items jsonb)
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
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  if not ${q.allowed("create_from_requirements.tenant", q.write)} then
    ${q.forbidden("not allowed to plan production")}
  end if;
  if jsonb_typeof(create_from_requirements.items) is distinct from 'array' or jsonb_array_length(create_from_requirements.items) = 0 then
    ${q.orderInvalid("items must be a non-empty array")}
  end if;
  if exists (select 1 from jsonb_array_elements(create_from_requirements.items) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'action', '') not in ('produce', 'purchase')
      or nullif(e ->> 'variantId', '') is null or coalesce(nullif(e ->> 'quantity', '')::numeric, 0) <= 0) then
    ${q.orderInvalid("each item has a variantId, an action of produce or purchase and a quantity above zero")}
  end if;
  select y.${loc.col("id")} into v_default_location from ${loc.table} y
  where y.${loc.col("tenant")} = create_from_requirements.tenant and ${loc.active("y")}
  order by y.${loc.col("code")}
  limit 1;
  for v_item in
    select e from jsonb_array_elements(create_from_requirements.items) e where e ->> 'action' = 'produce'
  loop
    v_orders := v_orders || jsonb_build_array(${fn("create_production_order")}(create_from_requirements.tenant,
      jsonb_strip_nulls(jsonb_build_object('variantId', v_item ->> 'variantId', 'quantity', v_item ->> 'quantity',
        'dueOn', v_item ->> 'dueOn', 'locationId', v_item ->> 'locationId'))));
  end loop;
  ${purchase}
  return jsonb_build_object('productionOrders', v_orders, 'purchaseOrders', ${requisitions ? "'[]'::jsonb" : "v_purchases"}, 'purchaseRequisitions', ${requisitions ? "v_purchases" : "'[]'::jsonb"});
end;
$$;
${userGrant(`${fn("create_from_requirements")}(${idType}, jsonb)`)}
`;
}
