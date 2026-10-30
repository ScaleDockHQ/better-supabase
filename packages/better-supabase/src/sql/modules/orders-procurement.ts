import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { fail, userGrant } from "../shared.ts";
import { locationsOf } from "./inventory-stock.ts";
import { linked } from "./manufacturing-sql.ts";
import { columns } from "./orders-shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { creditLimitSql, userPartySql } from "./procurement-sql.ts";

/**
 * The credit check of `place_order`: what the cart's user owes on open orders
 * plus `v_total` against the credit limit contacts keeps on their person. A
 * cart user who holds orders.override_credit passes. Empty without contacts'
 * credit columns.
 */
export function orderCreditSql(ctx: BlockSqlContext): string {
  const party = userPartySql(ctx, "v_cart.owner", "v_cart.tenant");

  if (party === undefined) {
    return "";
  }

  const o = columns(ctx, "orders");

  const override = ctx.permission(
    "overrideCredit",
    OPERATIONS["orders.overrideCredit"],
  );

  return creditLimitSql(ctx, {
    party,
    tenant: "v_cart.tenant",
    currency: "v_cart.currency",
    amount: "v_total",
    open: `select coalesce(sum(greatest(x.${o("total")} - x.${o("paidTotal")}, 0)), 0) from ${ctx.table("orders")} x
      where x.${o("customer")} = v_cart.owner and x.${o("tenant")} = v_cart.tenant and x.${o("currency")} = v_cart.currency
        and ${ctx.is("orders", "status", `x.${o("status")}`, ["cancelled", "refunded"], true)}`,
    override: ctx.scope.canUser("v_cart.owner", "v_cart.tenant", override),
    hint: "ORDER_CREDIT_LIMIT_EXCEEDED",
    what: "the order",
  });
}

const dropShips = (ctx: BlockSqlContext): boolean => {
  const inventory = linked(ctx, "inventory");

  return (
    inventory !== undefined &&
    inventory.hasTable("purchaseOrders") &&
    inventory.hasTable("purchaseOrderLines")
  );
};

/**
 * `purchase_order_from_order`: a draft purchase order of the inventory block
 * that ships an order's lines straight from the supplier to the customer.
 */
export function dropShipFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const inventory = linked(ctx, "inventory");

  if (inventory === undefined || !dropShips(ctx)) {
    return "";
  }

  const { fn } = names;
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");

  const po = (column: string): string =>
    inventory.col("purchaseOrders", column);

  const it = (column: string): string => inventory.col("items", column);
  const loc = locationsOf(inventory);

  const items = inventory.hasTable("items")
    ? inventory.table("items")
    : undefined;

  const lineLocation = ctx.has("orderLines", "location")
    ? `(select l.${ol("location")} from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id and l.${ol("location")} is not null limit 1)`
    : "null::uuid";

  const unitCost =
    items === undefined
      ? "0"
      : `coalesce((select round(y.${it("averageCost")})::bigint from ${items} y where y.${it("variant")} = l.${ol("variant")} and y.${it("currency")} = v_order.currency), 0)`;

  const marks = [
    inventory.has("purchaseOrders", "shipTo")
      ? `${po("shipTo")} = v_order.ship_to`
      : "",
    inventory.has("purchaseOrders", "originType")
      ? `${po("originType")} = 'order'`
      : "",
    inventory.has("purchaseOrders", "originId")
      ? `${po("originId")} = v_order.id::text`
      : "",
  ].filter((mark) => mark !== "");

  const mark =
    marks.length === 0
      ? ""
      : `
  update ${inventory.table("purchaseOrders")} x set ${marks.join(", ")}
  where x.${po("id")} = (v_purchase ->> 'id')::uuid;`;

  return `
-- A draft purchase order for an order's lines, shipped by the supplier
-- straight to the order's shipping address (drop ship): the supplier is a
-- config.subjects record (a contacts company by default), the location the
-- one the order's lines were reserved at or the first active one, the unit
-- cost the variant's average cost in the order's currency (0 without one;
-- edit the draft before placing it). Needs inventory.purchase.
create or replace function ${fn("purchase_order_from_order")}(order_id uuid, supplier_id text, supplier_type text default 'company', location uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_location uuid := purchase_order_from_order.location;
  v_lines jsonb;
  v_purchase jsonb;
begin
  select x.${o("id")} as id, x.${o("tenant")} as tenant, x.${o("currency")} as currency, x.${o("shippingAddress")} as ship_to
  into v_order from ${ctx.table("orders")} x where x.${o("id")} = purchase_order_from_order.order_id;
  if not found or not (auth.role() = 'service_role' or ${ctx.scope.can("v_order.tenant", names.read)}) then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  if purchase_order_from_order.supplier_id is null then
    ${fail("INVENTORY_SUPPLIER_INVALID", "a drop-ship purchase order names its supplier", "22023")}
  end if;
  v_location := coalesce(v_location, ${lineLocation}, (select y.${loc.col("id")} from ${loc.table} y
    where y.${loc.col("tenant")} = v_order.tenant and ${loc.active("y")} order by y.${loc.col("code")} limit 1));
  select jsonb_agg(jsonb_build_object('variantId', g.variant, 'quantity', g.quantity::text, 'unitCost', g.unit_cost::text)) into v_lines
  from (
    select l.${ol("variant")} as variant, sum(l.${ol("quantity")}) as quantity, max(${unitCost}) as unit_cost
    from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id and l.${ol("variant")} is not null
    group by 1
  ) g;
  if v_lines is null then
    ${fail("ORDERS_CART_EMPTY", "the order has no catalog lines to buy", "55000")}
  end if;
  v_purchase := ${inventory.fn("save_purchase_order")}(v_order.tenant, null, v_location, purchase_order_from_order.supplier_type,
    purchase_order_from_order.supplier_id, v_order.currency, null, v_lines, 'Drop ship');${mark}
  return v_purchase || jsonb_build_object('orderId', v_order.id, 'shipTo', v_order.ship_to);
end;
$$;
${userGrant(`${fn("purchase_order_from_order")}(uuid, text, text, uuid)`)}
`;
}

export function dropShipContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return dropShips(ctx)
    ? [
        {
          name: "purchase_order_from_order",
          args: ["uuid", "text", "text", "uuid"],
          returns: "jsonb",
        },
      ]
    : [];
}
