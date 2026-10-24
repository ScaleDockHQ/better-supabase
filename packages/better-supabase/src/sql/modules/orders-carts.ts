import type { BlockSqlContext } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { amountOf, columns, guard, serviceOnlyGuard } from "./orders-shared.ts";

const MAX_QUANTITY = 10_000;

const COUNTRY = "'^[A-Z]{2}$'";

/**
 * Raises unless `address` (jsonb) is null or an object with a two-letter
 * country.
 */
function addressCheck(address: string): string {
  return `if ${address} is not null and (jsonb_typeof(${address}) <> 'object' or (${address} ? 'country' and coalesce(${address} ->> 'country', '') !~ ${COUNTRY})) then
    ${fail("ORDERS_ADDRESS_INVALID", "an address is an object whose country is an ISO 3166-1 alpha-2 code", "22023")}
  end if;`;
}

/**
 * The SQL that loads the cart `id` into `v_cart` and raises unless the caller
 * owns it.
 */
function ownCart(
  ctx: BlockSqlContext,
  id: string,
  options: { readonly lock?: boolean; readonly readers?: string } = {},
): string {
  const c = columns(ctx, "carts");

  const readers =
    options.readers === undefined
      ? ""
      : ` or ${ctx.scope.can("v_cart.tenant", options.readers)}`;

  return `select x.${c("tenant")} as tenant, x.${c("user")} as owner, x.${c("status")} as status,
    x.${c("currency")} as currency, x.${c("priceList")} as price_list, x.${c("shippingAddress")} as shipping_address
  into v_cart from ${ctx.table("carts")} x where x.${c("id")} = ${id}${options.lock ? " for update" : ""};
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()${readers}) then
    ${fail("ORDERS_CART_NOT_FOUND", "cart not found", "P0002")}
  end if;`;
}

function openCart(): string {
  return `if v_cart.status <> 'open' then
    ${fail("ORDERS_CART_CLOSED", "the cart is no longer open", "55000")}
  end if;`;
}

/** Raises unless `variant` is an active product's variant in the cart's tenant. */
function sellable(ctx: BlockSqlContext, variant: string): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const p = columns(catalog, "products");

  return `if not exists (
    select 1 from ${catalog.table("variants")} cv join ${catalog.table("products")} cp on cp.${p("id")} = cv.${v("product")}
    where cv.${v("id")} = ${variant} and cv.${v("tenant")} = v_cart.tenant and cp.${p("status")} = 'active'
  ) then
    ${fail("ORDERS_VARIANT_UNAVAILABLE", "this variant is not for sale", "P0002")}
  end if;`;
}

export function shippingRateFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const rates = ctx.table("shippingRates");
  const s = columns(ctx, "shippingRates");
  const units = ctx.of("catalog").fn("currency_minor_units");
  const amount = (key: string): string => amountOf(`(data ->> '${key}')`);

  const kind = ctx.cast(
    "shippingRates",
    "kind",
    "coalesce(data ->> 'kind', 'flat')",
  );

  const freeOver = ctx.has("shippingRates", "freeOver");

  return `
-- Creates or updates a shipping rate: a flat amount, plus an amount per
-- started kilogram for weight rates, free from an order subtotal when
-- free_over is set. Countries are ISO 3166-1 alpha-2; none means anywhere.
-- Amounts are text in minor units.
create or replace function ${fn("save_shipping_rate")}(tenant ${ctx.idType}, rate uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_countries text[];
begin
  ${guard(names.scope, names.manage, "save_shipping_rate.tenant")}
  if jsonb_typeof(data) is distinct from 'object' then
    ${fail("ORDERS_RATE_INVALID", "the rate is an object", "22023")}
  end if;
  if ${units}(data ->> 'currency') is null then
    ${fail("ORDERS_CURRENCY_INVALID", "the currency is not an ISO 4217 code", "22023")}
  end if;
  ${
    freeOver
      ? ""
      : `if data ->> 'freeOver' is not null then
    ${fail("ORDERS_FREE_OVER_UNSUPPORTED", "this shipping rate table has no free-over column", "22023")}
  end if;
  `
  }if ${amount("amount")} is null
    or (data ? 'amountPerKg' and ${amount("amountPerKg")} is null)
    or (data ->> 'freeOver' is not null and ${amount("freeOver")} is null) then
    ${fail("ORDERS_AMOUNT_INVALID", "amounts are whole minor units of zero or more, as text", "22023")}
  end if;
  select coalesce(array_agg(value order by value), '{}') into v_countries
  from jsonb_array_elements_text(coalesce(data -> 'countries', '[]'::jsonb));
  if exists (select 1 from unnest(v_countries) as c(value) where c.value !~ ${COUNTRY}) then
    ${fail("ORDERS_ADDRESS_INVALID", "countries are ISO 3166-1 alpha-2 codes", "22023")}
  end if;
  if save_shipping_rate.rate is null then
    insert into ${rates} (${s("tenant")}, ${s("name")}, ${s("countries")}, ${s("currency")}, ${s("kind")}, ${s("amount")}, ${s("perKg")}, ${freeOver ? `${s("freeOver")}, ` : ""}${s("active")})
    values (save_shipping_rate.tenant, data ->> 'name', v_countries, data ->> 'currency', ${kind},
      ${amount("amount")}, coalesce(${amount("amountPerKg")}, 0), ${freeOver ? `${amount("freeOver")}, ` : ""}coalesce((data ->> 'active')::boolean, true))
    returning ${s("id")} into v_id;
  else
    update ${rates} x set ${s("name")} = data ->> 'name', ${s("countries")} = v_countries, ${s("currency")} = data ->> 'currency',
      ${s("kind")} = ${kind}, ${s("amount")} = ${amount("amount")}, ${s("perKg")} = coalesce(${amount("amountPerKg")}, 0),
      ${freeOver ? `${s("freeOver")} = ${amount("freeOver")}, ` : ""}${s("active")} = coalesce((data ->> 'active')::boolean, true), ${s("updatedAt")} = now()
    where x.${s("id")} = save_shipping_rate.rate and x.${s("tenant")} = save_shipping_rate.tenant
    returning x.${s("id")} into v_id;
    if v_id is null then
      ${fail("ORDERS_RATE_NOT_FOUND", "shipping rate not found", "P0002")}
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("save_shipping_rate")}(${ctx.idType}, uuid, jsonb)`)}

create or replace function ${fn("delete_shipping_rate")}(rate uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${s("tenant")} into v_tenant from ${rates} x where x.${s("id")} = delete_shipping_rate.rate;
  if not found then
    return false;
  end if;
  ${guard(names.scope, names.manage, "v_tenant")}
  delete from ${rates} x where x.${s("id")} = delete_shipping_rate.rate;
  return true;
end;
$$;
${userGrant(`${fn("delete_shipping_rate")}(uuid)`)}
`;
}

/** `cart_totals`: the internal pricing every cart read and checkout share. */
function totalsFunction(ctx: BlockSqlContext, names: OrdersNames): string {
  const { fn } = names;
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");
  const p = columns(catalog, "products");
  const c = columns(ctx, "carts");
  const cl = columns(ctx, "cartLines");
  const s = columns(ctx, "shippingRates");

  const or = (
    table: string,
    row: string,
    logical: string,
    type: string,
  ): string =>
    ctx.has(table, logical)
      ? `${row}.${ctx.col(table, logical)}`
      : `null::${type}`;

  const kind = catalog.has("products", "kind")
    ? `cp.${p("kind")}`
    : "'physical'::text";

  const weight = catalog.has("variants", "weight")
    ? `cv.${v("weight")}`
    : "null::integer";

  const title = catalog.has("variants", "title")
    ? `concat_ws(' / ', cp.${p("title")}, nullif(cv.${v("title")}, ''))`
    : `cp.${p("title")}`;

  const promotions = ctx.installed("promotions")
    ? ctx.of("promotions").fn("cart_discounts")
    : undefined;

  const discounts =
    promotions === undefined
      ? ""
      : `
  if jsonb_array_length(v_lines) > 0 then
    v_promo := ${promotions}(p_cart, v_lines);
    v_discounts := coalesce(v_promo -> 'lines', '{}'::jsonb);
    v_applied := coalesce(v_promo -> 'applied', '[]'::jsonb);
    v_free := coalesce((v_promo ->> 'freeShipping')::boolean, false);
    v_problems := v_problems || coalesce(v_promo -> 'problems', '[]'::jsonb);
  end if;`;

  return `
-- A cart's lines at today's catalog prices, its discounts, shipping and the
-- problems that keep it from checkout. Refreshes each line's price
-- snapshot. Internal: price_cart and place_order call it after their checks.
-- Amounts are text: JSON numbers lose bigint precision.
create or replace function ${fn("cart_totals")}(p_cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_line record;
  v_rate record;
  v_amount bigint;
  v_lines jsonb := '[]';
  v_problems jsonb := '[]';
  v_subtotal bigint := 0;
  v_discount bigint := 0;
  v_shipping bigint := 0;
  v_weight bigint := 0;
  v_ships boolean := false;
  v_free boolean := false;
  v_promo jsonb;
  v_discounts jsonb := '{}';
  v_applied jsonb := '[]';
  v_snapshot jsonb;
  v_country text;
begin
  select x.${c("tenant")} as tenant, x.${c("currency")} as currency, x.${c("priceList")} as price_list,
    x.${c("shippingAddress")} as shipping_address, x.${c("shippingRate")} as shipping_rate,
    x.${c("user")} as owner, x.${c("status")} as status, ${or("carts", "x", "email", "text")} as email, ${or("carts", "x", "billingAddress", "jsonb")} as billing_address
  into v_cart from ${ctx.table("carts")} x where x.${c("id")} = p_cart;
  for v_line in
    select l.${cl("id")} as id, l.${cl("variant")} as variant, l.${cl("quantity")} as quantity, l.${cl("unitAmount")} as unit_amount,
      cv.${v("sku")} as sku, ${title} as title, cp.${p("id")} as product, cp.${p("status")} as status,
      ${kind} as kind, ${weight} as weight
    from ${ctx.table("cartLines")} l
    join ${catalog.table("variants")} cv on cv.${v("id")} = l.${cl("variant")}
    join ${catalog.table("products")} cp on cp.${p("id")} = cv.${v("product")}
    where l.${cl("cart")} = p_cart
    order by l.${cl("createdAt")}, l.${cl("id")}
  loop
    v_amount := (${catalog.fn("variant_price")}(v_line.variant, v_cart.currency, v_cart.price_list, null) ->> 'amount')::bigint;
    if v_line.status <> 'active' or v_amount is null then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object('lineId', v_line.id, 'variantId', v_line.variant,
        'problem', case when v_line.status <> 'active' then 'unavailable' else 'unpriced' end));
      continue;
    end if;
    if v_line.unit_amount is distinct from v_amount then
      update ${ctx.table("cartLines")} x set ${cl("unitAmount")} = v_amount, ${cl("updatedAt")} = now() where x.${cl("id")} = v_line.id;
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'id', v_line.id, 'variantId', v_line.variant, 'productId', v_line.product, 'sku', v_line.sku, 'title', v_line.title,
      'quantity', v_line.quantity, 'unitAmount', v_amount::text, 'previousUnitAmount', v_line.unit_amount::text,
      'subtotal', (v_amount * v_line.quantity)::text, 'requiresShipping', v_line.kind = 'physical'));
    v_subtotal := v_subtotal + v_amount * v_line.quantity;
    if v_line.kind = 'physical' then
      v_ships := true;
      v_weight := v_weight + coalesce(v_line.weight, 0)::bigint * v_line.quantity;
    end if;
  end loop;${discounts}
  select coalesce(jsonb_agg(e.l || jsonb_build_object(
      'discount', coalesce(v_discounts ->> (e.l ->> 'id'), '0'),
      'total', ((e.l ->> 'subtotal')::bigint - coalesce((v_discounts ->> (e.l ->> 'id'))::bigint, 0))::text) order by e.n), '[]'::jsonb),
    coalesce(sum(coalesce((v_discounts ->> (e.l ->> 'id'))::bigint, 0)), 0)
  into v_lines, v_discount
  from jsonb_array_elements(v_lines) with ordinality as e(l, n);
  v_country := v_cart.shipping_address ->> 'country';
  if v_ships and v_cart.shipping_rate is not null then
    select x.${s("id")} as id, x.${s("name")} as name, x.${s("countries")} as countries, x.${s("kind")} as kind,
      x.${s("amount")} as amount, x.${s("perKg")} as per_kg, ${or("shippingRates", "x", "freeOver", "bigint")} as free_over
    into v_rate from ${ctx.table("shippingRates")} x
    where x.${s("id")} = v_cart.shipping_rate and x.${s("active")} and x.${s("currency")} = v_cart.currency;
    if not found or (cardinality(v_rate.countries) > 0 and (v_country is null or not v_country = any (v_rate.countries))) then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'shipping_unavailable'));
    else
      v_shipping := v_rate.amount + case when v_rate.kind = 'weight' then (v_rate.per_kg * v_weight + 999) / 1000 else 0 end;
      if v_free or (v_rate.free_over is not null and v_subtotal - v_discount >= v_rate.free_over) then
        v_shipping := 0;
      end if;
      v_snapshot := jsonb_build_object('rateId', v_rate.id, 'name', v_rate.name, 'amount', v_shipping::text);
    end if;
  elsif v_ships and exists (
    select 1 from ${ctx.table("shippingRates")} x
    where x.${s("tenant")} = v_cart.tenant and x.${s("active")} and x.${s("currency")} = v_cart.currency
  ) then
    v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'shipping_required'));
  end if;
  return jsonb_build_object(
    'cartId', p_cart, 'organizationId', v_cart.tenant, 'customerId', v_cart.owner, 'status', v_cart.status,
    'email', v_cart.email, 'shippingAddress', v_cart.shipping_address, 'billingAddress', v_cart.billing_address,
    'currency', v_cart.currency, 'lines', v_lines,
    'subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'shippingTotal', v_shipping::text,
    'total', (v_subtotal - v_discount + v_shipping)::text, 'requiresShipping', v_ships,
    'weightGrams', v_weight::text, 'shipping', v_snapshot, 'promotions', v_applied, 'problems', v_problems);
end;
$$;
revoke execute on function ${fn("cart_totals")}(uuid) from public, anon, authenticated;
`;
}

export function cartFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const carts = ctx.table("carts");
  const lines = ctx.table("cartLines");
  const c = columns(ctx, "carts");
  const cl = columns(ctx, "cartLines");
  const s = columns(ctx, "shippingRates");
  const catalog = ctx.of("catalog");
  const email = ctx.has("carts", "email");
  const billing = ctx.has("carts", "billingAddress");

  const moveCodes = ctx.installed("promotions")
    ? `
      perform ${ctx.of("promotions").fn("move_cart_codes")}(v_from.id, v_to);`
    : "";

  const lists =
    catalog.hasTable("priceLists") && catalog.has("prices", "priceList");

  const priceListCheck = lists
    ? `if create_cart.price_list is not null then
    if not (auth.role() = 'service_role' or ${ctx.scope.can("create_cart.tenant", names.manage)}) then
      ${fail("ORDERS_FORBIDDEN", "only staff can put a cart on a price list")}
    end if;
    if not exists (select 1 from ${catalog.table("priceLists")} x where x.${catalog.col("priceLists", "id")} = create_cart.price_list and x.${catalog.col("priceLists", "tenant")} = create_cart.tenant) then
      ${fail("ORDERS_PRICE_LIST_NOT_FOUND", "price list not found", "P0002")}
    end if;
  end if;`
    : `if create_cart.price_list is not null then
    ${fail("ORDERS_PRICE_LIST_NOT_FOUND", "the catalog has no price lists", "P0002")}
  end if;`;

  return `${totalsFunction(ctx, names)}
-- The caller's open cart in an organization and currency, created on first
-- use. Every signed-in user can have one, anonymous sign-ins included;
-- merge_carts moves it when the user signs up. Only staff set a price list.
create or replace function ${fn("create_cart")}(tenant ${ctx.idType}, currency text, price_list uuid default null, email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if auth.uid() is null then
    ${fail("ORDERS_SIGN_IN_REQUIRED", "sign in (anonymously is enough) to keep a cart")}
  end if;
  if ${catalog.fn("currency_minor_units")}(create_cart.currency) is null then
    ${fail("ORDERS_CURRENCY_INVALID", "the currency is not an ISO 4217 code", "22023")}
  end if;
  ${priceListCheck}${
    email
      ? ""
      : `
  if create_cart.email is not null then
    ${fail("ORDERS_EMAIL_UNSUPPORTED", "this cart table has no email column", "22023")}
  end if;`
  }
  insert into ${carts} as x (${c("tenant")}, ${c("user")}, ${c("currency")}, ${c("priceList")}${email ? `, ${c("email")}` : ""})
  values (create_cart.tenant, auth.uid(), create_cart.currency, create_cart.price_list${email ? ", create_cart.email" : ""})
  on conflict (${c("tenant")}, ${c("user")}, ${c("currency")}) where ${c("status")} = 'open' do update
    set ${c("priceList")} = coalesce(excluded.${c("priceList")}, x.${c("priceList")}),${
      email
        ? `
      ${c("email")} = coalesce(excluded.${c("email")}, x.${c("email")}),`
        : ""
    } ${c("updatedAt")} = now()
  returning x.${c("id")} into v_id;
  return jsonb_build_object('id', v_id, 'currency', create_cart.currency, 'status', 'open');
end;
$$;
${userGrant(`${fn("create_cart")}(${ctx.idType}, text, uuid, text)`)}

-- Adds units of a variant to the cart; a variant already in it gets more.
create or replace function ${fn("add_to_cart")}(cart uuid, variant uuid, quantity integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_id uuid;
  v_quantity integer;
begin
  ${ownCart(ctx, "add_to_cart.cart", { lock: true })}
  ${openCart()}
  if add_to_cart.quantity is null or add_to_cart.quantity < 1 then
    ${fail("ORDERS_QUANTITY_INVALID", "the quantity must be a positive whole number", "22023")}
  end if;
  ${sellable(ctx, "add_to_cart.variant")}
  select x.${cl("quantity")} + add_to_cart.quantity into v_quantity from ${lines} x
  where x.${cl("cart")} = add_to_cart.cart and x.${cl("variant")} = add_to_cart.variant;
  if coalesce(v_quantity, add_to_cart.quantity) > ${MAX_QUANTITY} then
    ${fail("ORDERS_QUANTITY_INVALID", `a cart line holds at most ${MAX_QUANTITY} units`, "22023")}
  end if;
  insert into ${lines} as x (${cl("tenant")}, ${cl("cart")}, ${cl("variant")}, ${cl("quantity")})
  values (v_cart.tenant, add_to_cart.cart, add_to_cart.variant, add_to_cart.quantity)
  on conflict (${cl("cart")}, ${cl("variant")}) do update
    set ${cl("quantity")} = x.${cl("quantity")} + excluded.${cl("quantity")}, ${cl("updatedAt")} = now()
  returning x.${cl("id")}, x.${cl("quantity")} into v_id, v_quantity;
  update ${carts} x set ${c("updatedAt")} = now() where x.${c("id")} = add_to_cart.cart;
  return jsonb_build_object('lineId', v_id, 'quantity', v_quantity);
end;
$$;
${userGrant(`${fn("add_to_cart")}(uuid, uuid, integer)`)}

-- Sets a variant's quantity in the cart; zero removes the line.
create or replace function ${fn("set_cart_line")}(cart uuid, variant uuid, quantity integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_id uuid;
begin
  ${ownCart(ctx, "set_cart_line.cart", { lock: true })}
  ${openCart()}
  if set_cart_line.quantity is null or set_cart_line.quantity < 0 or set_cart_line.quantity > ${MAX_QUANTITY} then
    ${fail("ORDERS_QUANTITY_INVALID", `the quantity is a whole number from 0 to ${MAX_QUANTITY}`, "22023")}
  end if;
  if set_cart_line.quantity = 0 then
    delete from ${lines} x where x.${cl("cart")} = set_cart_line.cart and x.${cl("variant")} = set_cart_line.variant;
    update ${carts} x set ${c("updatedAt")} = now() where x.${c("id")} = set_cart_line.cart;
    return jsonb_build_object('lineId', null, 'quantity', 0);
  end if;
  ${sellable(ctx, "set_cart_line.variant")}
  insert into ${lines} as x (${cl("tenant")}, ${cl("cart")}, ${cl("variant")}, ${cl("quantity")})
  values (v_cart.tenant, set_cart_line.cart, set_cart_line.variant, set_cart_line.quantity)
  on conflict (${cl("cart")}, ${cl("variant")}) do update
    set ${cl("quantity")} = excluded.${cl("quantity")}, ${cl("updatedAt")} = now()
  returning x.${cl("id")} into v_id;
  update ${carts} x set ${c("updatedAt")} = now() where x.${c("id")} = set_cart_line.cart;
  return jsonb_build_object('lineId', v_id, 'quantity', set_cart_line.quantity);
end;
$$;
${userGrant(`${fn("set_cart_line")}(uuid, uuid, integer)`)}

-- Sets the cart's email and addresses; a null argument keeps the value.
create or replace function ${fn("set_cart_details")}(cart uuid, email text default null, shipping_address jsonb default null, billing_address jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  ${ownCart(ctx, "set_cart_details.cart", { lock: true })}
  ${openCart()}
  ${addressCheck("set_cart_details.shipping_address")}
  ${addressCheck("set_cart_details.billing_address")}${
    email
      ? ""
      : `
  if set_cart_details.email is not null then
    ${fail("ORDERS_EMAIL_UNSUPPORTED", "this cart table has no email column", "22023")}
  end if;`
  }${
    billing
      ? ""
      : `
  if set_cart_details.billing_address is not null then
    ${fail("ORDERS_BILLING_ADDRESS_UNSUPPORTED", "this cart table has no billing address column", "22023")}
  end if;`
  }
  update ${carts} x set${
    email
      ? `
    ${c("email")} = coalesce(set_cart_details.email, x.${c("email")}),`
      : ""
  }
    ${c("shippingAddress")} = coalesce(set_cart_details.shipping_address, x.${c("shippingAddress")}),${
      billing
        ? `
    ${c("billingAddress")} = coalesce(set_cart_details.billing_address, x.${c("billingAddress")}),`
        : ""
    }
    ${c("updatedAt")} = now()
  where x.${c("id")} = set_cart_details.cart;
  return true;
end;
$$;
${userGrant(`${fn("set_cart_details")}(uuid, text, jsonb, jsonb)`)}

-- Picks one of the cart's shipping options, or clears it with null.
create or replace function ${fn("set_cart_shipping_rate")}(cart uuid, rate uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  ${ownCart(ctx, "set_cart_shipping_rate.cart", { lock: true })}
  ${openCart()}
  if set_cart_shipping_rate.rate is not null and not exists (
    select 1 from ${ctx.table("shippingRates")} x
    where x.${s("id")} = set_cart_shipping_rate.rate and x.${s("tenant")} = v_cart.tenant and x.${s("active")}
      and x.${s("currency")} = v_cart.currency
      and (cardinality(x.${s("countries")}) = 0 or (v_cart.shipping_address ->> 'country') = any (x.${s("countries")}))
  ) then
    ${fail("ORDERS_RATE_NOT_FOUND", "this shipping rate doesn't serve the cart", "P0002")}
  end if;
  update ${carts} x set ${c("shippingRate")} = set_cart_shipping_rate.rate, ${c("updatedAt")} = now()
  where x.${c("id")} = set_cart_shipping_rate.cart;
  return true;
end;
$$;
${userGrant(`${fn("set_cart_shipping_rate")}(uuid, uuid)`)}

-- The active rates that serve the cart's currency and shipping country,
-- each with what it costs for this cart.
create or replace function ${fn("shipping_options")}(cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_totals jsonb;
  v_after_discount bigint;
  v_weight bigint;
begin
  ${ownCart(ctx, "shipping_options.cart", { readers: names.read })}
  v_totals := ${fn("cart_totals")}(shipping_options.cart);
  v_after_discount := (v_totals ->> 'subtotal')::bigint - (v_totals ->> 'discountTotal')::bigint;
  v_weight := (v_totals ->> 'weightGrams')::bigint;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.${s("id")}, 'name', x.${s("name")}, 'kind', x.${s("kind")}, 'currency', x.${s("currency")},
      'amount', (case
${
  ctx.has("shippingRates", "freeOver")
    ? `        when x.${s("freeOver")} is not null and v_after_discount >= x.${s("freeOver")} then 0
`
    : ""
}        else x.${s("amount")} + case when x.${s("kind")} = 'weight' then (x.${s("perKg")} * v_weight + 999) / 1000 else 0 end
      end)::text) order by x.${s("amount")}, x.${s("name")})
    from ${ctx.table("shippingRates")} x
    where x.${s("tenant")} = v_cart.tenant and x.${s("active")} and x.${s("currency")} = v_cart.currency
      and (cardinality(x.${s("countries")}) = 0 or (v_cart.shipping_address ->> 'country') = any (x.${s("countries")}))
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("shipping_options")}(uuid)`)}

-- The cart at today's prices: lines, discounts, shipping, the pre-tax
-- total and what keeps it from checkout. Its owner and the organization's
-- order readers can price it.
create or replace function ${fn("price_cart")}(cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  ${ownCart(ctx, "price_cart.cart", { readers: names.read })}
  return ${fn("cart_totals")}(price_cart.cart);
end;
$$;
${userGrant(`${fn("price_cart")}(uuid)`)}

-- Moves a user's open carts to another user, such as an anonymous user who
-- signed up or signed in. A cart in the same organization and currency
-- takes the lines, adding up quantities, and its promotion codes. Returns
-- the carts moved or merged.
create or replace function ${fn("merge_carts")}(from_user uuid, to_user uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from record;
  v_to uuid;
  v_count integer := 0;
begin
  ${serviceOnlyGuard()}
  if merge_carts.from_user = merge_carts.to_user then
    return 0;
  end if;
  for v_from in
    select x.${c("id")} as id, x.${c("tenant")} as tenant, x.${c("currency")} as currency
    from ${carts} x where x.${c("user")} = merge_carts.from_user and x.${c("status")} = 'open'
    for update
  loop
    select x.${c("id")} into v_to from ${carts} x
    where x.${c("user")} = merge_carts.to_user and x.${c("tenant")} = v_from.tenant
      and x.${c("currency")} = v_from.currency and x.${c("status")} = 'open'
    for update;
    if v_to is null then
      update ${carts} x set ${c("user")} = merge_carts.to_user, ${c("updatedAt")} = now() where x.${c("id")} = v_from.id;
    else
      insert into ${lines} as x (${cl("tenant")}, ${cl("cart")}, ${cl("variant")}, ${cl("quantity")}, ${cl("unitAmount")})
      select l.${cl("tenant")}, v_to, l.${cl("variant")}, l.${cl("quantity")}, l.${cl("unitAmount")}
      from ${lines} l where l.${cl("cart")} = v_from.id
      on conflict (${cl("cart")}, ${cl("variant")}) do update
        set ${cl("quantity")} = least(x.${cl("quantity")} + excluded.${cl("quantity")}, ${MAX_QUANTITY}), ${cl("updatedAt")} = now();${moveCodes}
      update ${carts} x set ${c("status")} = 'abandoned', ${c("updatedAt")} = now() where x.${c("id")} = v_from.id;
    end if;
    v_to := null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("merge_carts")}(uuid, uuid)`)}
`;
}
