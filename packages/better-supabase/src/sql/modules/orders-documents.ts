import type { BlockSqlContext } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlString } from "../../core/template.ts";
import { countedLine, lineColumn } from "../line-items-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { variantTracked } from "./catalog-tracking.ts";
import {
  asService,
  assignNumber,
  columns,
  guard,
  orderFields,
  orderPayload,
} from "./orders-shared.ts";

/** The document type an order's stock allocations carry. */
const DOCUMENT = "'order'";

/** Whether orders keep where a document order came from. */
function hasOrigin(ctx: BlockSqlContext): boolean {
  return ctx.has("orders", "originType") && ctx.has("orders", "originId");
}

/**
 * PL/pgSQL that allocates each tracked line of order `v_order` at the best
 * location (or `location`), keeping what isn't available on backorder. Declares
 * nothing; the function declares `v_line`, `v_allocation` and `v_claims`.
 */
function allocateLines(ctx: BlockSqlContext, location: string): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const ol = columns(ctx, "orderLines");

  return `
  for v_line in
    select x.${ol("id")} as id, x.${ol("variant")} as variant, x.${ol("quantity")} as quantity, cv.${v("allowBackorder")} as backorder
    from ${ctx.table("orderLines")} x join ${catalog.table("variants")} cv on cv.${v("id")} = x.${ol("variant")}
    where x.${ol("order")} = v_order.id and ${variantTracked(catalog, "cv")}
    order by x.${ol("position")}
  loop
    ${asService(`v_allocation := ${inventory.fn("allocate_stock")}(v_order.tenant, v_line.variant, ${location}, v_line.quantity::numeric, ${DOCUMENT}, v_order.id::text, v_line.id::text, v_line.backorder);`)}
    update ${ctx.table("orderLines")} x set ${ol("location")} = (v_allocation ->> 'locationId')::uuid,
      ${ol("backordered")} = (v_allocation ->> 'backordered')::numeric > 0
    where x.${ol("id")} = v_line.id;
  end loop;`;
}

/**
 * PL/pgSQL that takes the stock of fulfillment `v_fulfillment` out through its
 * lines' allocations, with each fulfillment line's lot and serial detail. Lines
 * without an allocation (orders placed from a cart) took their stock at
 * payment.
 */
export function shipAllocations(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const a = columns(inventory, "allocations");
  const fl = columns(ctx, "fulfillmentLines");

  const detail = ctx.has("fulfillmentLines", "detail")
    ? `z.${fl("detail")}`
    : "null::jsonb";

  return `
  for v_line in
    select y.${a("id")} as allocation, z.${fl("quantity")} as quantity, ${detail} as detail
    from ${ctx.table("fulfillmentLines")} z
    join ${inventory.table("allocations")} y on y.${a("tenant")} = v_order.tenant and y.${a("documentType")} = ${DOCUMENT}
      and y.${a("documentId")} = v_order.id::text and y.${a("line")} = z.${fl("line")}::text and y.${a("status")} = 'open'
    where z.${fl("fulfillment")} = v_fulfillment.id
  loop
    ${asService(`perform ${inventory.fn("fulfill_allocation")}(v_line.allocation, v_line.quantity::numeric, v_line.detail);`)}
  end loop;`;
}

/** PL/pgSQL that releases the open stock allocations of order `v_order`. */
export function releaseAllocations(ctx: BlockSqlContext): string {
  if (!ctx.installed("inventory")) {
    return "";
  }

  return `
  ${asService(`perform ${ctx.of("inventory").fn("release_allocations")}(v_order.tenant, ${DOCUMENT}, v_order.id::text);`)}`;
}

/**
 * Orders made from documents rather than carts: from lines staff enter and from
 * an accepted quote. They start confirmed, without a payment window, and hold
 * their stock through allocations with backorders (ADR 0127).
 */
export function documentFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const p = columns(catalog, "products");
  const orders = ctx.table("orders");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const origin = hasOrigin(ctx);
  const email = ctx.has("orders", "email");
  const billing = ctx.has("orders", "billingAddress");

  const kind = catalog.has("products", "kind")
    ? `cp.${p("kind")}`
    : "'physical'::text";

  const title = catalog.has("variants", "title")
    ? `concat_ws(' / ', cp.${p("title")}, nullif(cv.${v("title")}, ''))`
    : `cp.${p("title")}`;

  const amount = (value: string): string =>
    `case when coalesce(${value}, '') ~ '^[0-9]{1,18}$' then (${value})::bigint end`;

  const placed = ctx.record({
    type: "order.placed",
    payload: orderPayload("v_order", [
      ["number", "v_order.number"],
      ["customerId", "v_order.customer"],
      ["currency", "v_order.currency"],
      ["subtotal", "(p_attrs ->> 'subtotal')"],
      ["discountTotal", "(p_attrs ->> 'discountTotal')"],
      ["shippingTotal", "(p_attrs ->> 'shippingTotal')"],
      ["taxTotal", "(p_attrs ->> 'taxTotal')"],
      ["total", "v_order.total::text"],
      [
        "units",
        `(select coalesce(sum(l.${ol("quantity")}), 0)::text from ${ctx.table("orderLines")} l where l.${ol("order")} = v_order.id)`,
      ],
    ]),
    subject: "'orders/' || v_order.id::text",
    tenant: "v_order.tenant",
    audit: false,
  });

  const fromQuote = ctx.installed("quotes")
    ? quoteFunction(ctx, names)
    : noQuoteFunction(names);

  return `
-- Inserts a confirmed order with computed lines and totals, allocates its
-- stock and records order.placed. p_attrs carries the totals as text and an
-- optional origin; an order with the same origin is returned instead.
-- Internal: order_from_lines and order_from_quote check first.
create or replace function ${fn("order_from_document")}(p_tenant ${ctx.idType}, p_attrs jsonb, p_lines jsonb, p_location uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_line record;
  v_allocation jsonb;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_claims text;
begin
  ${
    origin
      ? `if p_attrs -> 'origin' is not null then
    select x.${o("id")} into v_id from ${orders} x
    where x.${o("tenant")} = p_tenant and x.${o("originType")} = p_attrs #>> '{origin,type}' and x.${o("originId")} = p_attrs #>> '{origin,id}'
      and ${ctx.is("orders", "status", `x.${o("status")}`, ["cancelled"], true)}
    limit 1;
    if v_id is not null then
      return ${fn("order_json")}(v_id) || jsonb_build_object('created', false);
    end if;
  end if;`
      : `if p_attrs -> 'origin' is not null then
    ${fail("ORDERS_ORIGIN_UNSUPPORTED", "this orders table has no origin columns, so a document can't be ordered once", "22023")}
  end if;`
  }
  ${assignNumber(ctx, "order", "p_tenant", { seq: "v_seq", number: "v_number" })}
  insert into ${orders} (${o("tenant")}, ${o("number")}, ${o("sequence")}, ${o("customer")}, ${email ? `${o("email")}, ` : ""}${o("status")}, ${o("currency")},
    ${o("subtotal")}, ${o("discountTotal")}, ${o("shippingTotal")}, ${o("taxTotal")}, ${o("total")}, ${o("taxInclusive")},
    ${o("shippingAddress")}${billing ? `, ${o("billingAddress")}` : ""}${origin ? `, ${o("originType")}, ${o("originId")}` : ""})
  values (p_tenant, v_number, v_seq, nullif(p_attrs ->> 'customerId', '')::uuid, ${email ? "p_attrs ->> 'email', " : ""}${ctx.value("orders", "status", "confirmed")}, p_attrs ->> 'currency',
    (p_attrs ->> 'subtotal')::bigint, (p_attrs ->> 'discountTotal')::bigint, (p_attrs ->> 'shippingTotal')::bigint,
    (p_attrs ->> 'taxTotal')::bigint, (p_attrs ->> 'total')::bigint, coalesce((p_attrs ->> 'taxInclusive')::boolean, false),
    p_attrs -> 'shippingAddress'${billing ? ", p_attrs -> 'billingAddress'" : ""}${origin ? ", p_attrs #>> '{origin,type}', p_attrs #>> '{origin,id}'" : ""})
  returning ${o("id")} into v_id;
  insert into ${ctx.table("orderLines")} (${ol("tenant")}, ${ol("order")}, ${ol("position")}, ${ol("variant")}, ${ol("product")}, ${ol("sku")}, ${ol("title")},
    ${ol("quantity")}, ${ol("unitAmount")}, ${ol("subtotal")}, ${ol("discount")}, ${ol("tax")}, ${ol("total")}, ${ol("requiresShipping")})
  select p_tenant, v_id, e.n, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    (e.l ->> 'tax')::bigint, (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(p_lines) with ordinality as e(l, n);
  select ${orderFields(ctx, "x")} into v_order from ${orders} x where x.${o("id")} = v_id;${allocateLines(ctx, "p_location")}
  ${placed}
  return ${fn("order_json")}(v_id) || jsonb_build_object('created', true);
end;
$$;
revoke execute on function ${fn("order_from_document")}(${ctx.idType}, jsonb, jsonb, uuid) from public, anon, authenticated;

-- A confirmed order from lines staff enter, for sales that don't go through
-- a cart: phone, B2B and wholesale orders. lines: [{ variantId?, title?,
-- sku?, quantity, unitAmount?, discount?, tax? }]; a catalog line without a
-- unitAmount takes the variant's price. attrs: { currency, customerId?,
-- email?, shippingAddress?, billingAddress?, shippingTotal?, taxInclusive?,
-- locationId?, origin? { type, id } }. Amounts are minor units as text.
create or replace function ${fn("order_from_lines")}(tenant ${ctx.idType}, lines jsonb, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_attrs jsonb := coalesce(order_from_lines.attrs, '{}'::jsonb);
  v_currency text := v_attrs ->> 'currency';
  v_inclusive boolean := coalesce((v_attrs ->> 'taxInclusive')::boolean, false);
  v_shipping bigint := coalesce(${amount("v_attrs ->> 'shippingTotal'")}, 0);
  v_item record;
  v_lines jsonb := '[]';
  v_unit bigint;
  v_subtotal bigint := 0;
  v_discount bigint := 0;
  v_tax bigint := 0;
begin
  ${guard(names.scope, names.manage, "order_from_lines.tenant")}
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${fail("ORDERS_CURRENCY_INVALID", "attrs.currency is an ISO 4217 code", "22023")}
  end if;
  if jsonb_typeof(order_from_lines.lines) is distinct from 'array' or jsonb_array_length(order_from_lines.lines) = 0 then
    ${fail("ORDERS_LINES_INVALID", "lines is a non-empty list", "22023")}
  end if;
  if (v_attrs ? 'shippingTotal' and ${amount("v_attrs ->> 'shippingTotal'")} is null) then
    ${fail("ORDERS_AMOUNT_INVALID", "amounts are minor units of zero or more", "22023")}
  end if;
  for v_item in
    select e as raw, nullif(e ->> 'variantId', '')::uuid as variant, e ->> 'quantity' as quantity,
      cv.${v("id")} as found, cv.${v("tenant")} as variant_tenant, cv.${v("sku")} as sku, ${title} as title, cp.${p("id")} as product, ${kind} as kind
    from jsonb_array_elements(order_from_lines.lines) e
    left join ${catalog.table("variants")} cv on cv.${v("id")} = nullif(e ->> 'variantId', '')::uuid
    left join ${catalog.table("products")} cp on cp.${p("id")} = cv.${v("product")}
  loop
    if coalesce(v_item.quantity, '') !~ '^[1-9][0-9]{0,8}$' then
      ${fail("ORDERS_QUANTITY_INVALID", "each quantity is a whole number above zero", "22023")}
    end if;
    if v_item.variant is not null and (v_item.found is null or v_item.variant_tenant <> order_from_lines.tenant) then
      ${fail("ORDERS_VARIANT_NOT_FOUND", "a line's variant isn't in this organization", "P0002")}
    end if;
    if v_item.variant is null and coalesce(v_item.raw ->> 'title', '') = '' then
      ${fail("ORDERS_LINES_INVALID", "a line without a variant needs a title", "22023")}
    end if;
    if (v_item.raw ? 'unitAmount' and ${amount("v_item.raw ->> 'unitAmount'")} is null)
      or (v_item.raw ? 'discount' and ${amount("v_item.raw ->> 'discount'")} is null)
      or (v_item.raw ? 'tax' and ${amount("v_item.raw ->> 'tax'")} is null) then
      ${fail("ORDERS_AMOUNT_INVALID", "amounts are minor units of zero or more", "22023")}
    end if;
    v_unit := coalesce(${amount("v_item.raw ->> 'unitAmount'")},
      case when v_item.variant is not null then (${catalog.fn("variant_price")}(v_item.variant, v_currency, null, null) ->> 'amount')::bigint end);
    if v_unit is null then
      ${fail("ORDERS_LINE_UNPRICED", "a line has no unitAmount and its variant no price in this currency", "22023")}
    end if;
    if coalesce(${amount("v_item.raw ->> 'discount'")}, 0) > v_unit * v_item.quantity::bigint then
      ${fail("ORDERS_AMOUNT_INVALID", "a line's discount is more than its subtotal", "22023")}
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'variantId', v_item.variant, 'productId', v_item.product,
      'sku', coalesce(v_item.raw ->> 'sku', v_item.sku, ''), 'title', coalesce(nullif(v_item.raw ->> 'title', ''), v_item.title),
      'quantity', v_item.quantity, 'unitAmount', v_unit::text, 'subtotal', (v_unit * v_item.quantity::bigint)::text,
      'discount', coalesce(${amount("v_item.raw ->> 'discount'")}, 0)::text, 'tax', coalesce(${amount("v_item.raw ->> 'tax'")}, 0)::text,
      'total', (v_unit * v_item.quantity::bigint - coalesce(${amount("v_item.raw ->> 'discount'")}, 0))::text,
      'requiresShipping', case when v_item.variant is null then coalesce((v_item.raw ->> 'requiresShipping')::boolean, false) else v_item.kind = 'physical' end));
    v_subtotal := v_subtotal + v_unit * v_item.quantity::bigint;
    v_discount := v_discount + coalesce(${amount("v_item.raw ->> 'discount'")}, 0);
    v_tax := v_tax + coalesce(${amount("v_item.raw ->> 'tax'")}, 0);
  end loop;
  return ${fn("order_from_document")}(order_from_lines.tenant, v_attrs || jsonb_build_object(
    'subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'shippingTotal', v_shipping::text, 'taxTotal', v_tax::text,
    'total', (v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end)::text),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
end;
$$;
${userGrant(`${fn("order_from_lines")}(${ctx.idType}, jsonb, jsonb)`)}
${fromQuote}`;
}

/**
 * `order_from_quote` without the quotes block: the client always calls it, so
 * it exists and refuses.
 */
function noQuoteFunction(names: OrdersNames): string {
  const { fn } = names;

  return `
create or replace function ${fn("order_from_quote")}(quote uuid, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${fail("ORDERS_QUOTES_MISSING", "install the quotes block to order a quote", "22023")}
end;
$$;
${userGrant(`${fn("order_from_quote")}(uuid, jsonb)`)}
`;
}

/**
 * `order_from_quote`: the order of an accepted quote, once per quote. Each
 * counted line becomes an order line; a line whose product is a catalog variant
 * ships and holds its stock. The order takes the quote's totals.
 */
function quoteFunction(ctx: BlockSqlContext, names: OrdersNames): string {
  const { fn } = names;
  const quotes = ctx.of("quotes");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const p = columns(catalog, "products");
  const q = (column: string): string => quotes.col("quotes", column);
  const ql = (column: string): string => quotes.col("lines", column);

  const line = (column: string): string =>
    lineColumn(quotes, "lines", "x", column);

  const inclusive = quotes.has("quotes", "pricesIncludeTax")
    ? `v_quote.${q("pricesIncludeTax")}`
    : "false";

  const kind = catalog.has("products", "kind")
    ? `cp.${p("kind")}`
    : "'physical'::text";

  const variantType = sqlString(catalog.naming.rename("product_variant"));
  const isVariant = `${line("productType")}::text = ${variantType} and ${line("productId")} ~* '^[0-9a-f-]{36}$'`;

  return `
-- The confirmed order of an accepted quote, made once per quote: ordering it
-- again returns the same order. attrs takes customerId, email, the
-- addresses and locationId, as for order_from_lines.
create or replace function ${fn("order_from_quote")}(quote uuid, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote record;
  v_lines jsonb;
  v_attrs jsonb := coalesce(order_from_quote.attrs, '{}'::jsonb);
begin
  select * into v_quote from ${quotes.table("quotes")} x where x.${q("id")} = order_from_quote.quote;
  if v_quote.${q("id")} is null or not (auth.role() = 'service_role' or ${ctx.scope.can(`v_quote.${q("tenant")}`, names.manage)}) then
    ${fail("ORDERS_QUOTE_NOT_FOUND", "no such quote you can order", "P0002")}
  end if;
  if ${quotes.is("quotes", "status", `v_quote.${q("status")}`, ["accepted"], true)} then
    ${fail("ORDERS_QUOTE_NOT_ACCEPTED", "only an accepted quote becomes an order", "55000")}
  end if;
  if exists (select 1 from ${quotes.table("lines")} x where x.${ql("parent")} = v_quote.${q("id")} and ${countedLine(quotes, "lines", "x")}
    and x.${ql("quantity")} <> trunc(x.${ql("quantity")})) then
    ${fail("ORDERS_QUANTITY_INVALID", "an order line is a whole quantity; the quote has a fractional one", "22023")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'variantId', cv.${v("id")}, 'productId', cp.${p("id")}, 'sku', coalesce(cv.${v("sku")}, ''), 'title', x.${ql("description")},
      'quantity', x.${ql("quantity")}::integer, 'unitAmount', x.${ql("unitAmount")}::text,
      'subtotal', s.subtotal::text, 'discount', s.discount::text,
      'tax', (case when ${inclusive} then (s.subtotal - s.discount) - round((s.subtotal - s.discount) * 10000.0 / (10000 + s.rate))
        else round((s.subtotal - s.discount) * s.rate / 10000.0) end)::bigint::text,
      'total', (s.subtotal - s.discount)::text,
      'requiresShipping', coalesce(${kind} = 'physical', false)) order by x.${ql("position")}), '[]'::jsonb)
  into v_lines
  from ${quotes.table("lines")} x
  cross join lateral (select round(x.${ql("quantity")} * x.${ql("unitAmount")})::bigint as subtotal,
    round(round(x.${ql("quantity")} * x.${ql("unitAmount")}) * ${line("discountBps")} / 10000.0)::bigint as discount,
    ${line("taxRateBps")} as rate) s
  left join ${catalog.table("variants")} cv on ${isVariant} and cv.${v("id")} = ${line("productId")}::uuid and cv.${v("tenant")} = v_quote.${q("tenant")}
  left join ${catalog.table("products")} cp on cp.${p("id")} = cv.${v("product")}
  where x.${ql("parent")} = v_quote.${q("id")} and ${countedLine(quotes, "lines", "x")} and x.${ql("quantity")} > 0;
  if jsonb_array_length(v_lines) = 0 then
    ${fail("ORDERS_LINES_INVALID", "the quote has no lines to order", "55000")}
  end if;
  return ${fn("order_from_document")}(v_quote.${q("tenant")}, v_attrs || jsonb_build_object(
    'currency', v_quote.${q("currency")}, 'taxInclusive', ${inclusive},
    'subtotal', v_quote.${q(quotes.has("quotes", "listTotal") ? "listTotal" : "subtotal")}::text, 'discountTotal', ${quotes.has("quotes", "discountTotal") ? `v_quote.${q("discountTotal")}::text` : "'0'"}, 'shippingTotal', '0',
    'taxTotal', v_quote.${q("taxTotal")}::text, 'total', v_quote.${q("total")}::text,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote.${q("id")}::text)),
    v_lines, nullif(v_attrs ->> 'locationId', '')::uuid);
end;
$$;
${userGrant(`${fn("order_from_quote")}(uuid, jsonb)`)}
`;
}
