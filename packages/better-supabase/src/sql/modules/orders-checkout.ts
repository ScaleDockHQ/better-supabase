import type { BlockSqlContext } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { locationsOf, moveStock } from "./inventory-stock.ts";
import {
  amountOf,
  asService,
  assignNumber,
  columns,
  orderFields,
  orderPayload,
  paymentWindow,
  serviceOnlyGuard,
  transitionFunction,
} from "./orders-shared.ts";

/**
 * With the invoices block, the PL/pgSQL that turns a newly paid order into an
 * issued, paid invoice (`origin` the order) and takes its identifier as the
 * order's invoice number. Each line is billed at its net amount with the tax
 * rate its tax implies, so the invoice can differ from the order by rounding.
 */
function orderInvoice(
  ctx: BlockSqlContext,
): { readonly create: string; readonly id: string } | undefined {
  if (!ctx.installed("invoices")) {
    return undefined;
  }

  const invoices = ctx.of("invoices");

  const ic = (column: string): string =>
    sqlString(invoices.colName("invoices", column));

  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const net = `(l.${ol("total")} - l.${ol("tax")})`;

  const variantType = sqlString(
    ctx.of("catalog").naming.rename("product_variant"),
  );

  const lines = `(select coalesce(jsonb_agg(jsonb_build_object(
      'description', case when l.${ol("quantity")} = 1 then l.${ol("title")} else l.${ol("title")} || ' x ' || l.${ol("quantity")}::text end,
      'quantity', 1, 'unitAmount', ${net}::text, 'currency', v_order.currency,
      'taxRateBps', case when ${net} > 0 then round(l.${ol("tax")} * 10000.0 / ${net})::integer else 0 end,
      'product', case when l.${ol("variant")} is null then null else jsonb_build_object('type', ${variantType}, 'id', l.${ol("variant")}::text) end)
      order by l.${ol("position")}), '[]'::jsonb)
    from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id)
    || (select case when x.${o("shippingTotal")} > 0 then jsonb_build_array(jsonb_build_object('description', 'Shipping', 'quantity', 1, 'unitAmount', x.${o("shippingTotal")}::text, 'currency', v_order.currency)) else '[]'::jsonb end
    from ${ctx.table("orders")} x where x.${o("id")} = v_order.id)`;

  return {
    id: invoices.colName("invoices", "id"),
    create: `v_invoice := ${invoices.fn("create_invoice")}(v_order.tenant,
      jsonb_build_object('title', 'Order ' || v_order.number, 'currency', v_order.currency, 'termsDays', 0,
        'origin', jsonb_build_object('type', 'order', 'id', v_order.id::text)),
      ${lines});
    v_invoice := ${invoices.fn("issue_invoice")}((v_invoice ->> ${ic("id")})::uuid, current_date);
    v_invoice := ${invoices.fn("record_invoice_payment")}((v_invoice ->> ${ic("id")})::uuid, (v_invoice ->> ${ic("total")})::bigint,
      v_order.currency, now(), 'order', 'order:' || v_order.id::text);
    v_number := v_invoice ->> ${ic("identifier")};`,
  };
}

const PAYMENT_STATUSES =
  "('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled')";

/** Payment statuses a late webhook can't move a payment back from. */
const SETTLED = "('succeeded', 'failed', 'canceled')";

/**
 * `order_json(order)`: the order with its lines, payments, fulfillments,
 * returns and refunds.
 */
function orderJson(ctx: BlockSqlContext, names: OrdersNames): string {
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const p = columns(ctx, "payments");
  const f = columns(ctx, "fulfillments");
  const fl = columns(ctx, "fulfillmentLines");
  const r = columns(ctx, "returns");
  const rl = columns(ctx, "returnLines");
  const rf = columns(ctx, "refunds");

  const text = (alias: string, column: string): string =>
    `${alias}.${column}::text`;

  const or = (table: string, alias: string, logical: string): string =>
    ctx.has(table, logical) ? `${alias}.${ctx.col(table, logical)}` : "null";

  return `
-- The order as one object. Amounts are text. Internal: get_order and
-- place_order return it after their checks.
create or replace function ${names.fn("order_json")}(p_order uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x.${o("id")}, 'organizationId', x.${o("tenant")}, 'number', x.${o("number")}, 'cartId', x.${o("cart")},
    'customerId', x.${o("customer")}, 'email', ${or("orders", "x", "email")}, 'status', x.${o("status")}, 'currency', x.${o("currency")},
    'subtotal', ${text("x", o("subtotal"))}, 'discountTotal', ${text("x", o("discountTotal"))},
    'shippingTotal', ${text("x", o("shippingTotal"))}, 'taxTotal', ${text("x", o("taxTotal"))}, 'total', ${text("x", o("total"))},
    'paidTotal', ${text("x", o("paidTotal"))}, 'refundedTotal', ${text("x", o("refundedTotal"))}, 'taxInclusive', x.${o("taxInclusive")},
    'shippingAddress', x.${o("shippingAddress")}, 'billingAddress', ${or("orders", "x", "billingAddress")}, 'shipping', x.${o("shipping")},
    'promotions', x.${o("promotions")}, 'tax', x.${o("tax")}, 'taxTransaction', ${or("orders", "x", "taxTransaction")},
    'invoiceNumber', x.${o("invoiceNumber")}, 'invoicedAt', x.${o("invoicedAt")}, 'placedAt', x.${o("placedAt")},
    'paidAt', x.${o("paidAt")}, 'fulfilledAt', x.${o("fulfilledAt")}, 'completedAt', x.${o("completedAt")},
    'cancelledAt', x.${o("cancelledAt")}, 'cancelReason', ${or("orders", "x", "cancelReason")},
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l.${ol("id")}, 'variantId', l.${ol("variant")}, 'productId', l.${ol("product")}, 'sku', l.${ol("sku")},
        'title', l.${ol("title")}, 'quantity', l.${ol("quantity")}, 'unitAmount', ${text("l", ol("unitAmount"))},
        'subtotal', ${text("l", ol("subtotal"))}, 'discount', ${text("l", ol("discount"))}, 'tax', ${text("l", ol("tax"))},
        'total', ${text("l", ol("total"))}, 'requiresShipping', l.${ol("requiresShipping")}, 'locationId', l.${ol("location")},
        'reservationId', l.${ol("reservation")}, 'fulfilled', l.${ol("fulfilled")}, 'returned', l.${ol("returned")},
        'backordered', l.${ol("backordered")}) order by l.${ol("position")})
      from ${ctx.table("orderLines")} l where l.${ol("order")} = x.${o("id")}), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y.${p("id")}, 'provider', y.${p("provider")}, 'reference', y.${p("reference")}, 'status', y.${p("status")},
        'amount', ${text("y", p("amount"))}, 'captured', ${text("y", p("captured"))}, 'refunded', ${text("y", p("refunded"))},
        'createdAt', y.${p("createdAt")}) order by y.${p("createdAt")})
      from ${ctx.table("payments")} y where y.${p("order")} = x.${o("id")}), '[]'::jsonb),
    'fulfillments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y.${f("id")}, 'status', y.${f("status")}, 'locationId', y.${f("location")}, 'carrier', y.${f("carrier")},
        'trackingNumber', y.${f("trackingNumber")}, 'trackingUrl', ${or("fulfillments", "y", "trackingUrl")}, 'createdAt', y.${f("createdAt")},
        'shippedAt', y.${f("shippedAt")}, 'deliveredAt', y.${f("deliveredAt")},
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z.${fl("line")}, 'quantity', z.${fl("quantity")}))
          from ${ctx.table("fulfillmentLines")} z where z.${fl("fulfillment")} = y.${f("id")}), '[]'::jsonb)) order by y.${f("createdAt")})
      from ${ctx.table("fulfillments")} y where y.${f("order")} = x.${o("id")}), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y.${r("id")}, 'status', y.${r("status")}, 'reason', ${or("returns", "y", "reason")}, 'createdAt', y.${r("createdAt")},
        'receivedAt', y.${r("receivedAt")},
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z.${rl("line")}, 'quantity', z.${rl("quantity")}))
          from ${ctx.table("returnLines")} z where z.${rl("return")} = y.${r("id")}), '[]'::jsonb)) order by y.${r("createdAt")})
      from ${ctx.table("returns")} y where y.${r("order")} = x.${o("id")}), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y.${rf("id")}, 'paymentId', y.${rf("payment")}, 'returnId', y.${rf("return")}, 'amount', ${text("y", rf("amount"))},
        'status', y.${rf("status")}, 'reason', ${or("refunds", "y", "reason")}, 'providerReference', y.${rf("providerReference")},
        'createdAt', y.${rf("createdAt")}, 'completedAt', y.${rf("completedAt")}) order by y.${rf("createdAt")})
      from ${ctx.table("refunds")} y where y.${rf("order")} = x.${o("id")}), '[]'::jsonb)${extraFieldsJson("x", names.extras)})
  from ${ctx.table("orders")} x where x.${o("id")} = p_order
$$;
revoke execute on function ${names.fn("order_json")}(uuid) from public, anon, authenticated;
`;
}

/** The SQL that reserves each tracked line's stock at the best location. */
function reserveLines(ctx: BlockSqlContext, minutes: number): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const locations = locationsOf(inventory);
  const l = locations.col;
  const lv = columns(inventory, "levels");
  const ol = columns(ctx, "orderLines");

  return `
  for v_line in
    select x.${ol("id")} as id, x.${ol("variant")} as variant, x.${ol("quantity")} as quantity,
      cv.${v("trackInventory")} as tracked, cv.${v("allowBackorder")} as backorder
    from ${ctx.table("orderLines")} x join ${catalog.table("variants")} cv on cv.${v("id")} = x.${ol("variant")}
    where x.${ol("order")} = v_order.id
    order by x.${ol("position")}
  loop
    continue when not v_line.tracked;
    select loc.${l("id")} into v_location
    from ${locations.table} loc
    left join ${inventory.table("levels")} s on s.${lv("location")} = loc.${l("id")} and s.${lv("variant")} = v_line.variant
    where loc.${l("tenant")} = v_cart.tenant and ${locations.active("loc")} and (place_order.location is null or loc.${l("id")} = place_order.location)
    order by (coalesce(s.${lv("available")}, 0) >= v_line.quantity) desc, coalesce(s.${lv("available")}, 0) desc, loc.${l("code")}
    limit 1;
    if v_location is null then
      if not v_line.backorder then
        ${fail("ORDERS_OUT_OF_STOCK", "a line is out of stock", "23514")}
      end if;
      update ${ctx.table("orderLines")} x set ${ol("backordered")} = true where x.${ol("id")} = v_line.id;
      continue;
    end if;
    ${asService(`v_reservation := ${inventory.fn("reserve_stock")}(v_line.variant, v_location, v_line.quantity, 'order', v_order.id::text, now() + interval '${String(minutes)} minutes');`)}
    update ${ctx.table("orderLines")} x set ${ol("location")} = v_location, ${ol("reservation")} = (v_reservation ->> 'id')::uuid,
      ${ol("backordered")} = (v_reservation ->> 'available')::integer < 0
    where x.${ol("id")} = v_line.id;
  end loop;`;
}

/**
 * The SQL that turns each line's reservation into a sale once the order is
 * paid. An expired hold is released and the stock taken directly; a line the
 * stock can't cover any more is marked backordered.
 */
function commitLines(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const ol = columns(ctx, "orderLines");

  return `
    for v_line in
      select x.${ol("id")} as id, x.${ol("variant")} as variant, x.${ol("quantity")} as quantity,
        x.${ol("location")} as location, x.${ol("reservation")} as reservation
      from ${ctx.table("orderLines")} x
      where x.${ol("order")} = v_order.id and x.${ol("reservation")} is not null
      order by x.${ol("position")}
    loop
      begin
        ${asService(`perform ${inventory.fn("commit_reservation")}(v_line.reservation);`)}
      exception when sqlstate '55000' then
        begin
          ${asService(`perform ${inventory.fn("release_reservation")}(v_line.reservation);`)}
          perform ${moveStock(inventory, { tenant: "v_order.tenant", variant: "v_line.variant", location: "v_line.location", quantity: "-v_line.quantity", reason: "'sale'", referenceType: "'order'", referenceId: "v_order.id::text" })};
        exception when sqlstate '23514' then
          update ${ctx.table("orderLines")} x set ${ol("backordered")} = true where x.${ol("id")} = v_line.id;
        end;
      end;
    end loop;`;
}

function releaseLines(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const ol = columns(ctx, "orderLines");

  return `
  for v_line in
    select x.${ol("reservation")} as reservation from ${ctx.table("orderLines")} x
    where x.${ol("order")} = v_order.id and x.${ol("reservation")} is not null
  loop
    ${asService(`perform ${inventory.fn("release_reservation")}(v_line.reservation);`)}
  end loop;`;
}

export function checkoutFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const minutes = paymentWindow(ctx);
  const carts = ctx.table("carts");
  const orders = ctx.table("orders");
  const payments = ctx.table("payments");
  const c = columns(ctx, "carts");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const p = columns(ctx, "payments");

  const promotions = ctx.installed("promotions")
    ? ctx.of("promotions")
    : undefined;

  const invoice = orderInvoice(ctx);

  const taxOf = (key: string): string => amountOf(`(e ->> '${key}')`);

  const has = (table: string, logical: string): boolean =>
    ctx.has(table, logical);

  const cartOr = (logical: string, type: string): string =>
    has("carts", logical) ? `x.${c(logical)}` : `null::${type}`;

  const email = has("orders", "email");
  const billing = has("orders", "billingAddress");

  const load = (id: string, lock: boolean): string =>
    `select ${orderFields(ctx, "x")} into v_order from ${orders} x where x.${o("id")} = ${id}${lock ? " for update" : ""};`;

  const units = `(select coalesce(sum(l.${ol("quantity")}), 0)::text from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id)`;

  const cancelled = ctx.record({
    type: "order.cancelled",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["reason", "coalesce(p_reason, 'cancelled')"],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  });

  return `${transitionFunction(ctx, names)}${orderJson(ctx, names)}
-- Turns an open cart into an order: prices it again, refuses a total that
-- moved since the caller quoted tax (ORDERS_PRICE_CHANGED), numbers the
-- order, reserves its stock for the payment window and redeems its
-- promotions. tax is the TaxQuote as JSON (amounts as text) or null.
-- Placing the same cart again returns its order. Service only: the
-- TypeScript checkout calls the tax and payment providers around it.
${extraFieldsArg(names.extras).drop(fn("place_order"), "uuid, jsonb, bigint, uuid")}
create or replace function ${fn("place_order")}(cart uuid, tax jsonb default null, expected_total bigint default null, location uuid default null${extraFieldsArg(names.extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_order record;
  v_line record;
  v_priced jsonb;
  v_tax bigint := 0;
  v_line_tax bigint;
  v_invalid boolean;
  v_inclusive boolean := false;
  v_total bigint;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_location uuid;
  v_reservation jsonb;
  v_claims text;
begin
  ${serviceOnlyGuard()}
  select x.${c("tenant")} as tenant, x.${c("user")} as owner, x.${c("status")} as status, x.${c("currency")} as currency,
    ${cartOr("email", "text")} as email, x.${c("shippingAddress")} as shipping_address, ${cartOr("billingAddress", "jsonb")} as billing_address
  into v_cart from ${carts} x where x.${c("id")} = place_order.cart for update;
  if not found then
    ${fail("ORDERS_CART_NOT_FOUND", "cart not found", "P0002")}
  end if;
  if v_cart.status = 'converted' then
    select x.${o("id")} into v_id from ${orders} x where x.${o("cart")} = place_order.cart;
    if v_id is not null then
      return ${fn("order_json")}(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if v_cart.status <> 'open' then
    ${fail("ORDERS_CART_CLOSED", "the cart is no longer open", "55000")}
  end if;
  ${ctx.hook("before_order_place", [["uuid", "place_order.cart"]])}
  v_priced := ${fn("cart_totals")}(place_order.cart);
  if jsonb_array_length(v_priced -> 'lines') = 0 then
    ${fail("ORDERS_CART_EMPTY", "the cart has no lines to order", "55000")}
  end if;
  if jsonb_array_length(v_priced -> 'problems') > 0 then
    raise exception 'the cart can''t be ordered: %', v_priced -> 'problems' using errcode = '55000', hint = 'ORDERS_CART_INVALID';
  end if;
  if place_order.expected_total is not null and (v_priced ->> 'total')::bigint <> place_order.expected_total then
    ${fail("ORDERS_PRICE_CHANGED", "the cart's total changed; price it and quote tax again", "40001")}
  end if;
  if place_order.tax is not null then
    if jsonb_typeof(place_order.tax) <> 'object' or ${amountOf("(place_order.tax ->> 'totalTax')")} is null
      or coalesce(place_order.tax ->> 'currency', v_cart.currency) <> v_cart.currency then
      ${fail("ORDERS_TAX_INVALID", "tax is a quote in the cart's currency with a totalTax of zero or more", "22023")}
    end if;
    v_tax := ${amountOf("(place_order.tax ->> 'totalTax')")};
    v_inclusive := coalesce((place_order.tax ->> 'inclusive')::boolean, false);
    select coalesce(sum(${taxOf("tax")}), 0), coalesce(bool_or(${taxOf("tax")} is null), false)
    into v_line_tax, v_invalid
    from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) e;
    if v_invalid or (jsonb_array_length(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) > 0 and v_line_tax <> v_tax) then
      ${fail("ORDERS_TAX_INVALID", "the tax lines don't add up to totalTax", "22023")}
    end if;
  end if;
  v_total := (v_priced ->> 'total')::bigint + case when v_inclusive then 0 else v_tax end;
  ${assignNumber(ctx, "order", "v_cart.tenant", { seq: "v_seq", number: "v_number" })}
  insert into ${orders} (${o("tenant")}, ${o("number")}, ${o("sequence")}, ${o("cart")}, ${o("customer")}, ${email ? `${o("email")}, ` : ""}${o("currency")},
    ${o("subtotal")}, ${o("discountTotal")}, ${o("shippingTotal")}, ${o("taxTotal")}, ${o("total")}, ${o("taxInclusive")},
    ${o("shippingAddress")}, ${billing ? `${o("billingAddress")}, ` : ""}${o("shipping")}, ${o("promotions")}, ${o("tax")})
  values (v_cart.tenant, v_number, v_seq, place_order.cart, v_cart.owner, ${email ? "v_cart.email, " : ""}v_cart.currency,
    (v_priced ->> 'subtotal')::bigint, (v_priced ->> 'discountTotal')::bigint, (v_priced ->> 'shippingTotal')::bigint,
    v_tax, v_total, v_inclusive, v_cart.shipping_address, ${billing ? "v_cart.billing_address, " : ""}v_priced -> 'shipping',
    v_priced -> 'promotions', place_order.tax)
  returning ${o("id")} into v_id;${writeExtraColumns(orders, names.extras, "place_order.fields", `x.${o("id")} = v_id`)}
  insert into ${ctx.table("orderLines")} (${ol("tenant")}, ${ol("order")}, ${ol("position")}, ${ol("variant")}, ${ol("product")}, ${ol("sku")}, ${ol("title")},
    ${ol("quantity")}, ${ol("unitAmount")}, ${ol("subtotal")}, ${ol("discount")}, ${ol("tax")}, ${ol("total")}, ${ol("requiresShipping")})
  select v_cart.tenant, v_id, e.n, (e.l ->> 'variantId')::uuid, (e.l ->> 'productId')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    coalesce((select ${amountOf("(t ->> 'tax')")} from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) t
      where t ->> 'lineId' = e.l ->> 'id' limit 1), 0),
    (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(v_priced -> 'lines') with ordinality as e(l, n);
  ${load("v_id", false)}${reserveLines(ctx, minutes)}${
    promotions === undefined
      ? ""
      : `
  perform ${promotions.fn("redeem_promotions")}(v_order.id, v_priced -> 'promotions');`
  }
  update ${carts} x set ${c("status")} = 'converted', ${c("convertedAt")} = now(), ${c("updatedAt")} = now()
  where x.${c("id")} = place_order.cart;
  ${ctx.record({
    type: "order.placed",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["currency", "v_order.currency"],
      ["subtotal", "v_priced ->> 'subtotal'"],
      ["discountTotal", "v_priced ->> 'discountTotal'"],
      ["shippingTotal", "v_priced ->> 'shippingTotal'"],
      ["taxTotal", "v_tax::text"],
      ["total", "v_order.total::text"],
      ["units", units],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  })}
  ${ctx.hook("after_order_place", [["uuid", "v_order.id"]])}
  return ${fn("order_json")}(v_order.id) || jsonb_build_object('created', true);
end;
$$;
${serviceGrant(`${fn("place_order")}(uuid, jsonb, bigint, uuid${extraFieldsArg(names.extras).type})`)}

-- Records what a payment provider reports for an order's payment, keyed on
-- provider and reference, so a redelivered webhook changes nothing. A late
-- event never moves a settled payment back. Once the succeeded payments
-- cover the total, the order is paid: its reservations become sales, it
-- gets a gapless invoice number and order.paid is recorded. order may be
-- null for a payment recorded before. Amounts are minor units.
create or replace function ${fn("record_payment")}(order_id uuid, provider text, reference text, status text, currency text,
  amount bigint, captured bigint default 0, refunded bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order record;
  v_line record;
  v_id uuid := record_payment.order_id;
  v_paid bigint;
  v_newly boolean := false;
  v_seq bigint;
  v_number text;${invoice ? "\n  v_invoice jsonb;" : ""}
  v_claims text;
begin
  ${serviceOnlyGuard()}
  if v_id is null then
    select x.${p("order")} into v_id from ${payments} x
    where x.${p("provider")} = record_payment.provider and x.${p("reference")} = record_payment.reference;
  end if;
  ${load("v_id", true)}
  if not found then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  if record_payment.status is null or record_payment.status not in ${PAYMENT_STATUSES} then
    ${fail("ORDERS_PAYMENT_STATUS_INVALID", "unknown payment status", "22023")}
  end if;
  if record_payment.currency is distinct from v_order.currency then
    ${fail("ORDERS_CURRENCY_MISMATCH", "the payment is in another currency than the order", "22023")}
  end if;
  if coalesce(record_payment.amount, -1) < 0 or coalesce(record_payment.captured, 0) < 0 or coalesce(record_payment.refunded, 0) < 0 then
    ${fail("ORDERS_AMOUNT_INVALID", "payment amounts are zero or more", "22023")}
  end if;
  insert into ${payments} as x (${p("tenant")}, ${p("order")}, ${p("provider")}, ${p("reference")}, ${p("status")}, ${p("currency")},
    ${p("amount")}, ${p("captured")}, ${p("refunded")})
  values (v_order.tenant, v_order.id, record_payment.provider, record_payment.reference, ${ctx.cast("payments", "status", "record_payment.status")}, record_payment.currency,
    record_payment.amount, coalesce(record_payment.captured, 0), coalesce(record_payment.refunded, 0))
  on conflict (${p("provider")}, ${p("reference")}) do update set
    ${p("status")} = case when x.${p("status")} in ${SETTLED} and excluded.${p("status")} not in ${SETTLED} then x.${p("status")} else excluded.${p("status")} end,
    ${p("amount")} = excluded.${p("amount")},
    ${p("captured")} = greatest(x.${p("captured")}, excluded.${p("captured")}),
    ${p("refunded")} = greatest(x.${p("refunded")}, excluded.${p("refunded")}),
    ${p("updatedAt")} = now()
  where x.${p("order")} = excluded.${p("order")};
  if not found then
    ${fail("ORDERS_PAYMENT_CONFLICT", "this payment reference belongs to another order", "23505")}
  end if;
  select coalesce(sum(x.${p("captured")}), 0) into v_paid from ${payments} x
  where x.${p("order")} = v_order.id and x.${p("status")} = 'succeeded';
  update ${orders} x set ${o("paidTotal")} = v_paid, ${o("updatedAt")} = now() where x.${o("id")} = v_order.id;
  if v_order.status = 'pending_payment' and v_paid >= v_order.total then
    perform ${fn("order_transition")}(v_order.id, 'paid');${commitLines(ctx)}
    ${invoice ? invoice.create : assignNumber(ctx, "invoice", "v_order.tenant", { seq: "v_seq", number: "v_number" })}
    update ${orders} x set ${o("invoiceNumber")} = v_number, ${o("invoiceSequence")} = v_seq, ${o("invoicedAt")} = now()
    where x.${o("id")} = v_order.id;
    ${ctx.record({
      type: "order.paid",
      payload: orderPayload("v_order", [
        ["number", "v_order.number"],
        ["customerId", "v_order.customer"],
        ["currency", "v_order.currency"],
        ["total", "v_order.total::text"],
        ["units", units],
        ["invoiceNumber", "v_number"],
      ]),
      subject: "'orders/' || v_order.id::text",
      tenant: "v_order.tenant",
      key: "'order.paid:' || v_order.id::text",
      audit: false,
    })}
    v_newly := true;
  end if;
  return jsonb_build_object('orderId', v_order.id, 'status', (select x.${o("status")} from ${orders} x where x.${o("id")} = v_order.id),
    'paidTotal', v_paid::text, 'newlyPaid', v_newly,
    'invoiceNumber', coalesce(v_number, v_order.invoice_number)${invoice ? `, 'invoiceId', v_invoice ->> ${sqlString(invoice.id)}` : ""});
end;
$$;
${serviceGrant(`${fn("record_payment")}(uuid, text, text, text, text, bigint, bigint, bigint)`)}

-- Stores the tax provider's transaction for the sale, to reverse it on a refund.
create or replace function ${fn("set_order_tax_transaction")}(order_id uuid, tax_transaction jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${serviceOnlyGuard()}${
    has("orders", "taxTransaction")
      ? ""
      : `
  ${fail("ORDERS_TAX_TRANSACTION_UNSUPPORTED", "this order table has no tax transaction column", "22023")}`
  }
  update ${orders} x set ${has("orders", "taxTransaction") ? `${o("taxTransaction")} = set_order_tax_transaction.tax_transaction, ` : ""}${o("updatedAt")} = now()
  where x.${o("id")} = set_order_tax_transaction.order_id;
  return found;
end;
$$;
${serviceGrant(`${fn("set_order_tax_transaction")}(uuid, jsonb)`)}

-- Cancels an order waiting for payment: releases its stock and its
-- promotion redemptions. Internal: cancel_order and expire_orders check first.
create or replace function ${fn("order_cancel")}(p_order uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_line record;
  v_claims text;
begin
  ${load("p_order", true)}
  perform ${fn("order_transition")}(v_order.id, 'cancelled');${
    has("orders", "cancelReason")
      ? `
  update ${orders} x set ${o("cancelReason")} = p_reason where x.${o("id")} = v_order.id;`
      : ""
  }${releaseLines(ctx)}${
    promotions === undefined
      ? ""
      : `
  perform ${promotions.fn("release_promotions")}(v_order.id);`
  }
  ${cancelled}
end;
$$;
revoke execute on function ${fn("order_cancel")}(uuid, text) from public, anon, authenticated;

-- Cancels an order that is waiting for payment. Staff with orders.manage
-- and the customer who placed it can.
create or replace function ${fn("cancel_order")}(order_id uuid, reason text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  ${load("cancel_order.order_id", true)}
  if not found or not (auth.role() = 'service_role' or v_order.customer = auth.uid() or ${ctx.scope.can("v_order.tenant", names.read)}) then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or v_order.customer = auth.uid() or ${ctx.scope.can("v_order.tenant", names.manage)}) then
    ${fail("ORDERS_FORBIDDEN", "not allowed to cancel this order")}
  end if;
  if v_order.status = 'cancelled' then
    return false;
  end if;
  if v_order.status <> 'pending_payment' then
    ${fail("ORDERS_TRANSITION_INVALID", "only an order waiting for payment can be cancelled; refund a paid one", "55000")}
  end if;
  perform ${fn("order_cancel")}(v_order.id, cancel_order.reason);
  return true;
end;
$$;
${userGrant(`${fn("cancel_order")}(uuid, text)`)}

-- Cancels orders still waiting for payment once the payment window
-- (${String(minutes)} minutes) is over. Service only; run it from a job.
create or replace function ${fn("expire_orders")}(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  ${serviceOnlyGuard()}
  for v_id in
    select x.${o("id")} from ${orders} x
    where x.${o("status")} = 'pending_payment' and x.${o("placedAt")} < now() - interval '${String(minutes)} minutes'
    order by x.${o("placedAt")}
    limit greatest(coalesce(expire_orders.max_rows, 100), 1)
    for update skip locked
  loop
    perform ${fn("order_cancel")}(v_id, 'payment_expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_orders")}(integer)`)}

-- The order with its lines, payments, fulfillments, returns and refunds,
-- for its customer and the organization's order readers.
create or replace function ${fn("get_order")}(order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  ${load("get_order.order_id", false)}
  if not found or not (auth.role() = 'service_role' or v_order.customer = auth.uid() or ${ctx.scope.can("v_order.tenant", names.read)}) then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  return ${fn("order_json")}(v_order.id);
end;
$$;
${userGrant(`${fn("get_order")}(uuid)`)}
`;
}
