import type { BlockSqlContext } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { fail, userGrant } from "../shared.ts";
import { allocateLines } from "./orders-documents.ts";
import { columns, guard, orderFields, orderPayload } from "./orders-shared.ts";

/**
 * The states of an order staff enter: `draft` before it holds stock, and
 * `on_hold` while a confirmed or unpaid order waits on a person. A draft is
 * made by `order_from_lines` or `order_from_quote` with `attrs.draft`.
 */
export function staffOrderFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const orders = ctx.table("orders");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");

  const load = (id: string): string =>
    `select ${orderFields(ctx, "x")} into v_order from ${orders} x where x.${o("id")} = ${id} for update;
  if not found then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;`;

  const units = `(select coalesce(sum(l.${ol("quantity")}), 0)::text from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id)`;

  const money = (column: string): string =>
    `(select z.${o(column)}::text from ${orders} z where z.${o("id")} = v_order.id)`;

  const placed = ctx.record({
    type: "order.placed",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["currency", "v_order.currency"],
      ["subtotal", money("subtotal")],
      ["discountTotal", money("discountTotal")],
      ["shippingTotal", money("shippingTotal")],
      ["taxTotal", "v_order.tax_total::text"],
      ["total", "v_order.total::text"],
      ["units", units],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  });

  const held = ctx.record({
    type: "order.hold_placed",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["reason", "nullif(trim(hold_order.reason), '')"],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  });

  const released = ctx.record({
    type: "order.hold_released",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["status", "v_target"],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  });

  const holds = ctx.has("orders", "heldFrom")
    ? `
-- Puts an order that waits for payment, or a confirmed one, on hold: it can't
-- be paid into, fulfilled or expire until the hold is released. Its stock
-- stays reserved. reason is for the people who release it.
create or replace function ${fn("hold_order")}(order_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_from text;
begin
  ${load("hold_order.order_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_order.status::text not in ('pending_payment', 'confirmed') then
    ${fail("ORDERS_TRANSITION_INVALID", "only an order waiting for payment or a confirmed one can be put on hold", "55000")}
  end if;
  v_from := ${fn("order_transition")}(v_order.id, 'on_hold');
  update ${orders} x set ${o("heldFrom")} = v_from, ${o("heldAt")} = now(),${ctx.has("orders", "holdReason") ? ` ${o("holdReason")} = nullif(trim(hold_order.reason), ''),` : ""} ${o("updatedAt")} = now()
  where x.${o("id")} = v_order.id;
  ${held}
  return ${fn("order_json")}(v_order.id);
end;
$$;
${userGrant(`${fn("hold_order")}(uuid, text)`)}

-- Releases a hold: the order goes back to the status it was on hold from.
create or replace function ${fn("release_order_hold")}(order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_target text;
begin
  ${load("release_order_hold.order_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_order.status::text <> 'on_hold' then
    ${fail("ORDERS_TRANSITION_INVALID", "the order isn't on hold", "55000")}
  end if;
  select coalesce(x.${o("heldFrom")}, 'confirmed') into v_target from ${orders} x where x.${o("id")} = v_order.id;
  perform ${fn("order_transition")}(v_order.id, v_target);
  update ${orders} x set ${o("heldFrom")} = null, ${o("heldAt")} = null,${ctx.has("orders", "holdReason") ? ` ${o("holdReason")} = null,` : ""} ${o("updatedAt")} = now()
  where x.${o("id")} = v_order.id;
  ${released}
  return ${fn("order_json")}(v_order.id);
end;
$$;
${userGrant(`${fn("release_order_hold")}(uuid)`)}
`
    : "";

  return `
-- Confirms a draft order: it is allocated stock at the best location (or
-- location), the rest on backorder, and records order.placed. A draft that
-- was never confirmed can be cancelled with cancel_order.
create or replace function ${fn("confirm_draft_order")}(order_id uuid, location uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_line record;
  v_allocation jsonb;
  v_claims text;
begin
  ${load("confirm_draft_order.order_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_order.status::text <> 'draft' then
    ${fail("ORDERS_TRANSITION_INVALID", "only a draft order can be confirmed", "55000")}
  end if;
  perform ${fn("order_transition")}(v_order.id, 'confirmed');${allocateLines(ctx, "confirm_draft_order.location")}
  ${placed}
  return ${fn("order_json")}(v_order.id);
end;
$$;
${userGrant(`${fn("confirm_draft_order")}(uuid, uuid)`)}
${holds}`;
}
