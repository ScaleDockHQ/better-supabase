import type { ModuleContext } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import {
  columns,
  guard,
  orderFields,
  orderPayload,
  serviceOnlyGuard,
} from "./orders-shared.ts";

function restock(ctx: ModuleContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const m = columns(inventory, "movements");

  return `
    if receive_return.restock and v_line.variant is not null and coalesce(receive_return.location, v_line.location) is not null
      and exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = v_line.variant and cv.${v("trackInventory")}) then
      insert into ${inventory.table("movements")} (${m("tenant")}, ${m("variant")}, ${m("location")}, ${m("quantity")}, ${m("reason")}, ${m("referenceType")}, ${m("referenceId")})
      values (v_order.tenant, v_line.variant, coalesce(receive_return.location, v_line.location), v_line.quantity, 'return', 'order_return', receive_return.return_id::text);
    end if;`;
}

export function afterSaleFunctions(
  ctx: ModuleContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const orders = ctx.table("orders");
  const lines = ctx.table("orderLines");
  const fulfillments = ctx.table("fulfillments");
  const fulfillmentLines = ctx.table("fulfillmentLines");
  const returns = ctx.table("returns");
  const returnLines = ctx.table("returnLines");
  const refunds = ctx.table("refunds");
  const payments = ctx.table("payments");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const f = columns(ctx, "fulfillments");
  const fl = columns(ctx, "fulfillmentLines");
  const r = columns(ctx, "returns");
  const rl = columns(ctx, "returnLines");
  const rf = columns(ctx, "refunds");
  const p = columns(ctx, "payments");

  const load = (id: string): string =>
    `select ${orderFields(ctx, "x")} into v_order from ${orders} x where x.${o("id")} = ${id} for update;
  if not found then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;`;

  const subject = "'orders/' || v_order.id::text";

  const event = (
    type: string,
    extra: readonly (readonly [string, string])[],
    key?: string,
  ): string =>
    ctx.record({
      type,
      payload: orderPayload("v_order", [
        ["number", "v_order.number"],
        ["customerId", "v_order.customer"],
        ...extra,
      ]),
      subject,
      tenant: "v_order.tenant",
      ...(key === undefined ? {} : { key }),
      audit: false,
    });

  // Fulfillment and return events are about the order's parts; their id is
  // the fulfillment or return and the subject stays the order.
  const partEvent = (
    type: string,
    id: string,
    extra: readonly (readonly [string, string])[],
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', ${id}, 'orderId', v_order.id, 'number', v_order.number${extra.map(([k, value]) => `, '${k}', ${value}`).join("")})`,
      subject,
      tenant: "v_order.tenant",
      audit: false,
    });

  const loadFulfillment = (id: string): string =>
    `select x.${f("id")} as id, x.${f("order")} as order_id, x.${f("status")} as status into v_fulfillment
  from ${fulfillments} x where x.${f("id")} = ${id} for update;
  if not found then
    ${fail("ORDERS_FULFILLMENT_NOT_FOUND", "fulfillment not found", "P0002")}
  end if;
  ${load("v_fulfillment.order_id")}`;

  const loadReturn = (id: string): string =>
    `select x.${r("id")} as id, x.${r("order")} as order_id, x.${r("status")} as status into v_return
  from ${returns} x where x.${r("id")} = ${id} for update;
  if not found then
    ${fail("ORDERS_RETURN_NOT_FOUND", "return not found", "P0002")}
  end if;
  ${load("v_return.order_id")}`;

  return `
-- Fulfills lines of a paid order from one location. lines is
-- [{lineId, quantity}]; null fulfills everything not yet fulfilled.
create or replace function ${fn("create_fulfillment")}(order_id uuid, lines jsonb default null, location uuid default null,
  carrier text default null, tracking_number text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_item record;
  v_requested jsonb;
  v_id uuid;
begin
  ${load("create_fulfillment.order_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_order.status <> 'paid' then
    ${fail("ORDERS_NOT_PAID", "only a paid order can be fulfilled", "55000")}
  end if;
  ${ctx.hook("before_fulfillment_create", [["uuid", "v_order.id"]])}
  v_requested := coalesce(create_fulfillment.lines, (
    select jsonb_agg(jsonb_build_object('lineId', l.${ol("id")}, 'quantity', l.${ol("quantity")} - l.${ol("fulfilled")}) order by l.${ol("position")})
    from ${lines} l where l.${ol("order")} = v_order.id and l.${ol("quantity")} > l.${ol("fulfilled")}));
  if v_requested is null or jsonb_typeof(v_requested) <> 'array' or jsonb_array_length(v_requested) = 0 then
    ${fail("ORDERS_NOTHING_TO_FULFILL", "no lines left to fulfill", "55000")}
  end if;
  insert into ${fulfillments} (${f("tenant")}, ${f("order")}, ${f("location")}, ${f("carrier")}, ${f("trackingNumber")}, ${f("trackingUrl")})
  values (v_order.tenant, v_order.id,
    coalesce(create_fulfillment.location, (select l.${ol("location")} from ${lines} l where l.${ol("order")} = v_order.id and l.${ol("location")} is not null order by l.${ol("position")} limit 1)),
    create_fulfillment.carrier, create_fulfillment.tracking_number, create_fulfillment.tracking_url)
  returning ${f("id")} into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, (e ->> 'quantity')::integer as quantity from jsonb_array_elements(v_requested) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      ${fail("ORDERS_QUANTITY_INVALID", "each quantity is a whole number above zero", "22023")}
    end if;
    update ${lines} x set ${ol("fulfilled")} = x.${ol("fulfilled")} + v_item.quantity
    where x.${ol("id")} = v_item.line and x.${ol("order")} = v_order.id and x.${ol("fulfilled")} + v_item.quantity <= x.${ol("quantity")};
    if not found then
      ${fail("ORDERS_FULFILLMENT_INVALID", "a line isn't on this order or has less left to fulfill", "22023")}
    end if;
    insert into ${fulfillmentLines} as x (${fl("tenant")}, ${fl("fulfillment")}, ${fl("line")}, ${fl("quantity")})
    values (v_order.tenant, v_id, v_item.line, v_item.quantity)
    on conflict (${fl("fulfillment")}, ${fl("line")}) do update set ${fl("quantity")} = x.${fl("quantity")} + excluded.${fl("quantity")};
  end loop;
  ${ctx.hook("after_fulfillment_create", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'pending');
end;
$$;
${userGrant(`${fn("create_fulfillment")}(uuid, jsonb, uuid, text, text, text)`)}

-- Marks a fulfillment shipped. Once every line has shipped, the order is
-- fulfilled.
create or replace function ${fn("ship_fulfillment")}(fulfillment uuid, carrier text default null, tracking_number text default null, tracking_url text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  ${loadFulfillment("ship_fulfillment.fulfillment")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_fulfillment.status = 'shipped' then
    return false;
  end if;
  if v_fulfillment.status <> 'pending' then
    ${fail("ORDERS_TRANSITION_INVALID", "only a pending fulfillment can ship", "55000")}
  end if;
  update ${fulfillments} x set ${f("status")} = 'shipped', ${f("shippedAt")} = now(),
    ${f("carrier")} = coalesce(ship_fulfillment.carrier, x.${f("carrier")}),
    ${f("trackingNumber")} = coalesce(ship_fulfillment.tracking_number, x.${f("trackingNumber")}),
    ${f("trackingUrl")} = coalesce(ship_fulfillment.tracking_url, x.${f("trackingUrl")})
  where x.${f("id")} = v_fulfillment.id;
  ${partEvent("fulfillment.shipped", "v_fulfillment.id", [
    [
      "carrier",
      `(select x.${f("carrier")} from ${fulfillments} x where x.${f("id")} = v_fulfillment.id)`,
    ],
    [
      "trackingNumber",
      `(select x.${f("trackingNumber")} from ${fulfillments} x where x.${f("id")} = v_fulfillment.id)`,
    ],
  ])}
  if v_order.status = 'paid'
    and not exists (select 1 from ${lines} l where l.${ol("order")} = v_order.id and l.${ol("fulfilled")} < l.${ol("quantity")})
    and not exists (select 1 from ${fulfillments} x where x.${f("order")} = v_order.id and x.${f("status")} = 'pending') then
    perform ${fn("order_transition")}(v_order.id, 'fulfilled');
    ${event("order.fulfilled", [])}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("ship_fulfillment")}(uuid, text, text, text)`)}

-- Marks a shipped fulfillment delivered, from staff or a carrier webhook.
-- Once everything is delivered, the order is completed.
create or replace function ${fn("deliver_fulfillment")}(fulfillment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  ${loadFulfillment("deliver_fulfillment.fulfillment")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_fulfillment.status = 'delivered' then
    return false;
  end if;
  if v_fulfillment.status <> 'shipped' then
    ${fail("ORDERS_TRANSITION_INVALID", "only a shipped fulfillment can be delivered", "55000")}
  end if;
  update ${fulfillments} x set ${f("status")} = 'delivered', ${f("deliveredAt")} = now() where x.${f("id")} = v_fulfillment.id;
  ${partEvent("fulfillment.delivered", "v_fulfillment.id", [])}
  if v_order.status = 'fulfilled'
    and not exists (select 1 from ${fulfillments} x where x.${f("order")} = v_order.id and x.${f("status")} in ('pending', 'shipped')) then
    perform ${fn("order_transition")}(v_order.id, 'completed');
    ${event("order.completed", [])}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("deliver_fulfillment")}(uuid)`)}

-- Cancels a fulfillment that hasn't shipped; its lines can be fulfilled again.
create or replace function ${fn("cancel_fulfillment")}(fulfillment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  ${loadFulfillment("cancel_fulfillment.fulfillment")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_fulfillment.status = 'cancelled' then
    return false;
  end if;
  if v_fulfillment.status <> 'pending' then
    ${fail("ORDERS_TRANSITION_INVALID", "a shipped fulfillment can't be cancelled; request a return", "55000")}
  end if;
  update ${lines} x set ${ol("fulfilled")} = x.${ol("fulfilled")} - y.${fl("quantity")}
  from ${fulfillmentLines} y
  where y.${fl("fulfillment")} = v_fulfillment.id and x.${ol("id")} = y.${fl("line")};
  update ${fulfillments} x set ${f("status")} = 'cancelled' where x.${f("id")} = v_fulfillment.id;
  return true;
end;
$$;
${userGrant(`${fn("cancel_fulfillment")}(uuid)`)}

-- Requests a return of fulfilled lines. lines is [{lineId, quantity}].
-- The customer who placed the order and staff with orders.manage can.
create or replace function ${fn("request_return")}(order_id uuid, lines jsonb, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_item record;
  v_id uuid;
  v_open integer;
  v_units integer := 0;
begin
  ${load("request_return.order_id")}
  if not (auth.role() = 'service_role' or v_order.customer = auth.uid() or ${ctx.scope.can("v_order.tenant", names.manage)}) then
    ${fail("ORDERS_FORBIDDEN", "not allowed to return this order")}
  end if;
  if v_order.status not in ('paid', 'fulfilled', 'completed') then
    ${fail("ORDERS_TRANSITION_INVALID", "only a paid order can be returned", "55000")}
  end if;
  if request_return.lines is null or jsonb_typeof(request_return.lines) <> 'array' or jsonb_array_length(request_return.lines) = 0 then
    ${fail("ORDERS_RETURN_INVALID", "lines is a non-empty array of {lineId, quantity}", "22023")}
  end if;
  insert into ${returns} (${r("tenant")}, ${r("order")}, ${r("reason")})
  values (v_order.tenant, v_order.id, request_return.reason)
  returning ${r("id")} into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, (e ->> 'quantity')::integer as quantity from jsonb_array_elements(request_return.lines) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      ${fail("ORDERS_QUANTITY_INVALID", "each quantity is a whole number above zero", "22023")}
    end if;
    select coalesce(sum(y.${rl("quantity")}), 0) into v_open
    from ${returnLines} y join ${returns} z on z.${r("id")} = y.${rl("return")}
    where y.${rl("line")} = v_item.line and z.${r("status")} = 'requested';
    if not exists (select 1 from ${lines} l where l.${ol("id")} = v_item.line and l.${ol("order")} = v_order.id
      and l.${ol("fulfilled")} - l.${ol("returned")} - v_open >= v_item.quantity) then
      ${fail("ORDERS_RETURN_INVALID", "a line isn't on this order or has fewer fulfilled units left to return", "22023")}
    end if;
    insert into ${returnLines} as x (${rl("tenant")}, ${rl("return")}, ${rl("line")}, ${rl("quantity")})
    values (v_order.tenant, v_id, v_item.line, v_item.quantity)
    on conflict (${rl("return")}, ${rl("line")}) do update set ${rl("quantity")} = x.${rl("quantity")} + excluded.${rl("quantity")};
    v_units := v_units + v_item.quantity;
  end loop;
  ${partEvent("return.requested", "v_id", [
    ["quantity", "v_units::text"],
    ["reason", "request_return.reason"],
  ])}
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'requested', 'quantity', v_units);
end;
$$;
${userGrant(`${fn("request_return")}(uuid, jsonb, text)`)}

-- Receives a requested return. With restock, tracked units go back on hand
-- at location (or where the line was reserved). Refund it with create_refund.
create or replace function ${fn("receive_return")}(return_id uuid, restock boolean default true, location uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_return record;
  v_order record;
  v_line record;
  v_units integer := 0;
begin
  ${loadReturn("receive_return.return_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_return.status = 'received' then
    return false;
  end if;
  if v_return.status <> 'requested' then
    ${fail("ORDERS_TRANSITION_INVALID", "only a requested return can be received", "55000")}
  end if;
  for v_line in
    select y.${rl("line")} as line, y.${rl("quantity")} as quantity, l.${ol("variant")} as variant, l.${ol("location")} as location
    from ${returnLines} y join ${lines} l on l.${ol("id")} = y.${rl("line")}
    where y.${rl("return")} = v_return.id
  loop
    update ${lines} x set ${ol("returned")} = x.${ol("returned")} + v_line.quantity where x.${ol("id")} = v_line.line;${restock(ctx)}
    v_units := v_units + v_line.quantity;
  end loop;
  update ${returns} x set ${r("status")} = 'received', ${r("receivedAt")} = now() where x.${r("id")} = v_return.id;
  ${partEvent("return.received", "v_return.id", [["quantity", "v_units::text"]])}
  return true;
end;
$$;
${userGrant(`${fn("receive_return")}(uuid, boolean, uuid)`)}

create or replace function ${fn("reject_return")}(return_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_return record;
  v_order record;
begin
  ${loadReturn("reject_return.return_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  if v_return.status <> 'requested' then
    ${fail("ORDERS_TRANSITION_INVALID", "only a requested return can be rejected", "55000")}
  end if;
  update ${returns} x set ${r("status")} = 'rejected' where x.${r("id")} = v_return.id;
  return true;
end;
$$;
${userGrant(`${fn("reject_return")}(uuid)`)}

-- Starts a refund against the order's captured payment: amount null
-- refunds what is left. The TypeScript block sends it to the payment
-- provider and finishes it with complete_refund.
create or replace function ${fn("create_refund")}(order_id uuid, amount bigint default null, return_id uuid default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_pending bigint;
  v_left bigint;
  v_amount bigint;
  v_payment record;
  v_id uuid;
begin
  ${load("create_refund.order_id")}
  ${guard(names.scope, names.manage, "v_order.tenant")}
  ${ctx.hook("before_refund_create", [["uuid", "v_order.id"]])}
  if create_refund.return_id is not null and not exists (
    select 1 from ${returns} x where x.${r("id")} = create_refund.return_id and x.${r("order")} = v_order.id) then
    ${fail("ORDERS_RETURN_NOT_FOUND", "return not found on this order", "P0002")}
  end if;
  select coalesce(sum(x.${rf("amount")}), 0) into v_pending from ${refunds} x
  where x.${rf("order")} = v_order.id and x.${rf("status")} = 'pending';
  v_left := v_order.paid_total - v_order.refunded_total - v_pending;
  v_amount := coalesce(create_refund.amount, v_left);
  if v_amount <= 0 or v_amount > v_left then
    ${fail("ORDERS_REFUND_INVALID", "the amount is above zero and at most what was paid and not refunded yet", "22023")}
  end if;
  select y.${p("id")} as id, y.${p("provider")} as provider, y.${p("reference")} as reference into v_payment
  from ${payments} y
  where y.${p("order")} = v_order.id and y.${p("status")} = 'succeeded'
    and y.${p("captured")} - y.${p("refunded")} - coalesce((select sum(z.${rf("amount")}) from ${refunds} z
      where z.${rf("payment")} = y.${p("id")} and z.${rf("status")} = 'pending'), 0) >= v_amount
  order by y.${p("createdAt")} desc
  limit 1;
  if not found then
    ${fail("ORDERS_REFUND_INVALID", "no single captured payment covers this amount; refund in parts", "22023")}
  end if;
  insert into ${refunds} (${rf("tenant")}, ${rf("order")}, ${rf("payment")}, ${rf("return")}, ${rf("amount")}, ${rf("currency")}, ${rf("reason")})
  values (v_order.tenant, v_order.id, v_payment.id, create_refund.return_id, v_amount, v_order.currency, create_refund.reason)
  returning ${rf("id")} into v_id;
  ${ctx.hook("after_refund_create", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'paymentId', v_payment.id, 'provider', v_payment.provider,
    'paymentReference', v_payment.reference, 'amount', v_amount::text, 'currency', v_order.currency, 'status', 'pending');
end;
$$;
${userGrant(`${fn("create_refund")}(uuid, bigint, uuid, text)`)}

-- Records the payment provider's answer to a refund, found by its id or,
-- from a webhook, by the provider's refund id. pending only stores that
-- id. A succeeded refund adds to the order's refunded total and records
-- order.refunded; once everything paid is refunded, the order is
-- refunded. Repeating it changes nothing.
create or replace function ${fn("complete_refund")}(refund uuid, status text, provider_reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refund record;
  v_order record;
  v_total bigint;
begin
  ${serviceOnlyGuard()}
  if complete_refund.status is null or complete_refund.status not in ('pending', 'succeeded', 'failed') then
    ${fail("ORDERS_REFUND_STATUS_INVALID", "status is pending, succeeded or failed", "22023")}
  end if;
  select x.${rf("id")} as id, x.${rf("order")} as order_id, x.${rf("payment")} as payment, x.${rf("amount")} as amount,
    x.${rf("status")} as status
  into v_refund from ${refunds} x
  where (complete_refund.refund is not null and x.${rf("id")} = complete_refund.refund)
    or (complete_refund.refund is null and x.${rf("providerReference")} = complete_refund.provider_reference)
  for update;
  if not found then
    ${fail("ORDERS_REFUND_NOT_FOUND", "refund not found", "P0002")}
  end if;
  ${load("v_refund.order_id")}
  if v_refund.status = 'pending' and complete_refund.status = 'pending' then
    update ${refunds} x set ${rf("providerReference")} = coalesce(complete_refund.provider_reference, x.${rf("providerReference")})
    where x.${rf("id")} = v_refund.id;
  elsif v_refund.status = 'pending' then
    update ${refunds} x set ${rf("status")} = complete_refund.status, ${rf("completedAt")} = now(),
      ${rf("providerReference")} = coalesce(complete_refund.provider_reference, x.${rf("providerReference")})
    where x.${rf("id")} = v_refund.id;
    if complete_refund.status = 'succeeded' then
      update ${payments} x set ${p("refunded")} = x.${p("refunded")} + v_refund.amount, ${p("updatedAt")} = now()
      where x.${p("id")} = v_refund.payment;
      update ${orders} x set ${o("refundedTotal")} = x.${o("refundedTotal")} + v_refund.amount, ${o("updatedAt")} = now()
      where x.${o("id")} = v_order.id
      returning x.${o("refundedTotal")} into v_total;
      if v_total >= v_order.paid_total and v_order.status in ('paid', 'fulfilled', 'completed') then
        perform ${fn("order_transition")}(v_order.id, 'refunded');
      end if;
      ${event(
        "order.refunded",
        [
          ["currency", "v_order.currency"],
          ["amount", "v_refund.amount::text"],
          ["refundedTotal", "v_total::text"],
          [
            "status",
            `(select x.${o("status")} from ${orders} x where x.${o("id")} = v_order.id)`,
          ],
        ],
        "'order.refunded:' || v_refund.id::text",
      )}
    end if;
  end if;
  return (select jsonb_build_object('id', x.${rf("id")}, 'orderId', x.${rf("order")}, 'status', x.${rf("status")},
      'amount', x.${rf("amount")}::text, 'orderStatus', y.${o("status")}, 'refundedTotal', y.${o("refundedTotal")}::text)
    from ${refunds} x join ${orders} y on y.${o("id")} = x.${rf("order")} where x.${rf("id")} = v_refund.id);
end;
$$;
${serviceGrant(`${fn("complete_refund")}(uuid, text, text)`)}
`;
}
