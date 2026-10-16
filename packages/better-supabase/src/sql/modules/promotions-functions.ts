import type { ModuleContext } from "../context.ts";
import type { ModuleScope } from "../scope.ts";

import {
  columnsObject,
  fail,
  fieldsArg,
  fieldsParam,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { amountOf, columns } from "./orders-shared.ts";

export interface PromotionsNames {
  /** The block's scope checks. */
  readonly scope: ModuleScope;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly read: string;
}

/** Codes a cart can hold at once. */
const MAX_CART_CODES = 5;

/** Codes one `create_promotion_codes` call can generate. */
const MAX_GENERATED = 10000;

/** Generated code characters: no 0/O or 1/I. */
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function guard(names: PromotionsNames, tenant: string): string {
  return `if not (auth.role() = 'service_role' or ${names.scope.can(tenant, names.manage)}) then
    ${fail("PROMOTIONS_FORBIDDEN", "not allowed to manage these promotions")}
  end if;`;
}

/** `options.extraColumns`, added to the promotions table. */
export const promotionExtras = (
  ctx: ModuleContext,
): ReturnType<ModuleContext["extraColumns"]> => ctx.extraColumns("promotions");

/** Normalizes a shopper-typed code: trimmed and upper case. */
const normalized = (code: string): string => `upper(btrim(${code}))`;

export function promotionFunctions(
  ctx: ModuleContext,
  names: PromotionsNames,
): string {
  const { fn } = names;
  const extras = promotionExtras(ctx);
  const catalog = ctx.of("catalog");
  const p = columns(ctx, "promotions");
  const r = columns(ctx, "redemptions");
  const promotions = ctx.table("promotions");
  const units = catalog.fn("currency_minor_units");
  const targetTables: Readonly<Record<string, string | undefined>> = {
    products: catalog.table("products"),
    categories:
      catalog.hasTable("categories") && catalog.hasTable("productCategories")
        ? catalog.table("categories")
        : undefined,
    collections:
      catalog.hasTable("collections") && catalog.hasTable("collectionProducts")
        ? catalog.table("collections")
        : undefined,
  };
  const scopes = [
    "order",
    ...Object.keys(targetTables).filter(
      (key) => targetTables[key] !== undefined,
    ),
  ];
  const targetCheck = Object.entries(targetTables)
    .flatMap(([scope, table]) =>
      table === undefined
        ? []
        : [
            `    when '${scope}' then (select count(*) from ${table} x where x.${catalog.col(scope === "products" ? "products" : scope, "id")} = any (v_targets) and x.${catalog.col(scope === "products" ? "products" : scope, "tenant")} = v_tenant)`,
          ],
    )
    .join("\n");
  const amount = (key: string): string => amountOf(`(data ->> '${key}')`);
  const fields: readonly (readonly [string, string])[] = [
    ["name", "data ->> 'name'"],
    ["description", "data ->> 'description'"],
    ["kind", "v_kind"],
    ["percent", "v_percent"],
    [
      "currency",
      "case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end",
    ],
    ["amount", `case when v_kind = 'fixed' then ${amount("amount")} end`],
    ["minSubtotal", amount("minSubtotal")],
    ["scope", "v_scope"],
    ["targets", "v_targets"],
    ["startsAt", "(data ->> 'startsAt')::timestamptz"],
    ["endsAt", "(data ->> 'endsAt')::timestamptz"],
    ["usageLimit", "(data ->> 'usageLimit')::integer"],
    ["perCustomerLimit", "(data ->> 'perCustomerLimit')::integer"],
    ["stackable", "coalesce((data ->> 'stackable')::boolean, false)"],
    ["priority", "coalesce((data ->> 'priority')::integer, 0)"],
    ["automatic", "coalesce((data ->> 'automatic')::boolean, false)"],
    ["active", "coalesce((data ->> 'active')::boolean, true)"],
  ];
  return `
-- Creates or updates a promotion. data holds name, description, kind
-- (percentage, fixed or free_shipping), percent, currency, amount and
-- minSubtotal (minor units as text), scope (order, products, categories or
-- collections) with targets, startsAt, endsAt, usageLimit,
-- perCustomerLimit, stackable, priority, automatic and active.
create or replace function ${fn("save_promotion")}(tenant ${ctx.idType}, promotion uuid, data jsonb${fieldsParam(extras)})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType} := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if v_id is not null then
    select x.${p("tenant")} into v_tenant from ${promotions} x where x.${p("id")} = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      ${fail("PROMOTIONS_NOT_FOUND", "promotion not found", "P0002")}
    end if;
  end if;
  ${guard(names, "v_tenant")}
  if jsonb_typeof(data) is distinct from 'object' then
    ${fail("PROMOTIONS_INVALID", "data is an object", "22023")}
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    ${fail("PROMOTIONS_INVALID", "kind is percentage, fixed or free_shipping", "22023")}
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      ${fail("PROMOTIONS_INVALID", "percent is a number above 0 and at most 100, with up to two decimals", "22023")}
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and (${amount("amount")} is null or ${amount("amount")} <= 0) then
    ${fail("PROMOTIONS_INVALID", "a fixed promotion has an amount above zero", "22023")}
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and (${amount("minSubtotal")} is null or ${amount("minSubtotal")} <= 0) then
    ${fail("PROMOTIONS_INVALID", "minSubtotal is an amount above zero", "22023")}
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or ${units}(v_currency) is null) then
    ${fail("PROMOTIONS_INVALID", "an amount needs an ISO 4217 currency", "22023")}
  end if;
  if v_scope not in (${scopes.map((scope) => `'${scope}'`).join(", ")}) then
    ${fail("PROMOTIONS_INVALID", `scope is ${scopes.join(", ")}`, "22023")}
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    ${fail("PROMOTIONS_INVALID", "targets is an array of ids", "22023")}
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    ${fail("PROMOTIONS_INVALID", "an order promotion has no targets; the other scopes need at least one", "22023")}
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
${targetCheck}
    else 0 end) then
    ${fail("PROMOTIONS_INVALID", "every target is a product, category or collection of this organization", "22023")}
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    ${fail("PROMOTIONS_INVALID", "endsAt is after startsAt", "22023")}
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    ${fail("PROMOTIONS_INVALID", "a usage limit is a whole number above zero", "22023")}
  end if;
  ${ctx.hook("before_promotion_save", [["uuid", "v_id"]])}
  if v_id is null then
    insert into ${promotions} (${p("tenant")}, ${fields.map(([key]) => p(key)).join(", ")})
    values (v_tenant, ${fields.map(([, value]) => value).join(", ")})
    returning ${p("id")} into v_id;
  else
    update ${promotions} x set
${fields.map(([key, value]) => `      ${p(key)} = ${value},`).join("\n")}
      ${p("updatedAt")} = now()
    where x.${p("id")} = v_id;
  end if;${writeExtraColumns(promotions, extras, "save_promotion.fields", `x.${p("id")} = v_id`)}
  if coalesce((data ->> 'active')::boolean, true) then
    ${ctx.hook("before_promotion_activate", [["uuid", "v_id"]])}
  end if;
  ${ctx.hook("after_promotion_save", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id${
    extras.length === 0
      ? ""
      : `, 'fields', (select ${columnsObject(
          "x",
          extras.map((extra) => extra.name),
        )} from ${promotions} x where x.${p("id")} = v_id)`
  });
end;
$$;
${userGrant(`${fn("save_promotion")}(${ctx.idType}, uuid, jsonb${fieldsArg(extras)})`)}

-- before_promotion_activate(promotion) runs after the write, so it reads
-- the promotion as it will be; raising refuses the activation.
create or replace function ${fn("set_promotion_active")}(promotion uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${promotions} x where x.${p("id")} = set_promotion_active.promotion;
  if not found then
    ${fail("PROMOTIONS_NOT_FOUND", "promotion not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  update ${promotions} x set ${p("active")} = set_promotion_active.active, ${p("updatedAt")} = now()
  where x.${p("id")} = set_promotion_active.promotion;
  if set_promotion_active.active then
    ${ctx.hook("before_promotion_activate", [["uuid", "set_promotion_active.promotion"]])}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("set_promotion_active")}(uuid, boolean)`)}

-- Deletes a promotion nobody redeemed; deactivate one that was.
create or replace function ${fn("delete_promotion")}(promotion uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${promotions} x where x.${p("id")} = delete_promotion.promotion;
  if not found then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  if exists (select 1 from ${ctx.table("redemptions")} x where x.${r("promotion")} = delete_promotion.promotion) then
    ${fail("PROMOTIONS_IN_USE", "the promotion was redeemed; deactivate it instead", "55000")}
  end if;
  delete from ${promotions} x where x.${p("id")} = delete_promotion.promotion;
  return true;
end;
$$;
${userGrant(`${fn("delete_promotion")}(uuid)`)}
`;
}

export function codeFunctions(
  ctx: ModuleContext,
  names: PromotionsNames,
): string {
  const { fn } = names;
  const orders = ctx.of("orders");
  const p = columns(ctx, "promotions");
  const k = columns(ctx, "codes");
  const cc = columns(ctx, "cartCodes");
  const c = columns(orders, "carts");
  const codes = ctx.table("codes");
  return `
-- Adds codes to a promotion: the given ones, or count generated ones of
-- the prefix and eight random characters. Codes are stored upper case and
-- are unique per organization.
create or replace function ${fn("create_promotion_codes")}(promotion uuid, codes text[] default null,
  count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_code text;
  v_id uuid;
  v_out jsonb := '[]';
  v_prefix text := coalesce(${normalized("create_promotion_codes.prefix")}, '');
  v_bytes bytea;
  v_attempts integer := 0;
begin
  select x.${p("tenant")} into v_tenant from ${ctx.table("promotions")} x where x.${p("id")} = create_promotion_codes.promotion;
  if not found then
    ${fail("PROMOTIONS_NOT_FOUND", "promotion not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if (create_promotion_codes.codes is null) = (create_promotion_codes.count is null) then
    ${fail("PROMOTIONS_INVALID", "pass codes or a count", "22023")}
  end if;
  if create_promotion_codes.count is not null and (create_promotion_codes.count < 1 or create_promotion_codes.count > ${MAX_GENERATED}) then
    ${fail("PROMOTIONS_INVALID", `count is from 1 to ${MAX_GENERATED}`, "22023")}
  end if;
  if create_promotion_codes.usage_limit is not null and create_promotion_codes.usage_limit < 1 then
    ${fail("PROMOTIONS_INVALID", "a usage limit is a whole number above zero", "22023")}
  end if;
  if v_prefix !~ '^[A-Z0-9_-]{0,32}$' then
    ${fail("PROMOTIONS_INVALID", "a prefix has up to 32 letters, digits, dashes or underscores", "22023")}
  end if;
  if create_promotion_codes.codes is not null then
    foreach v_code in array create_promotion_codes.codes loop
      v_code := ${normalized("v_code")};
      if v_code is null or v_code !~ '^[A-Z0-9_-]{3,40}$' then
        ${fail("PROMOTIONS_CODE_FORMAT", "a code has 3 to 40 letters, digits, dashes or underscores", "22023")}
      end if;
      begin
        insert into ${codes} (${k("tenant")}, ${k("promotion")}, ${k("code")}, ${k("usageLimit")})
        values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
        returning ${k("id")} into v_id;
      exception when unique_violation then
        ${fail("PROMOTIONS_CODE_TAKEN", "another promotion uses this code", "23505")}
      end;
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
    end loop;
    return v_out;
  end if;
  while jsonb_array_length(v_out) < create_promotion_codes.count loop
    v_attempts := v_attempts + 1;
    if v_attempts > create_promotion_codes.count * 4 + 10 then
      ${fail("PROMOTIONS_CODE_SPACE", "couldn't generate enough unique codes; use a longer prefix", "55000")}
    end if;
    v_bytes := extensions.gen_random_bytes(8);
    v_code := v_prefix;
    for i in 0..7 loop
      v_code := v_code || substr('${ALPHABET}', (get_byte(v_bytes, i) % ${ALPHABET.length}) + 1, 1);
    end loop;
    insert into ${codes} (${k("tenant")}, ${k("promotion")}, ${k("code")}, ${k("usageLimit")})
    values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
    on conflict do nothing
    returning ${k("id")} into v_id;
    if v_id is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
      v_id := null;
    end if;
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("create_promotion_codes")}(uuid, text[], integer, text, integer)`)}

-- Deletes a code nobody redeemed.
create or replace function ${fn("delete_promotion_code")}(code uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_used integer;
begin
  select x.${k("tenant")}, x.${k("redemptions")} into v_tenant, v_used from ${codes} x where x.${k("id")} = delete_promotion_code.code;
  if not found then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  if v_used > 0 then
    ${fail("PROMOTIONS_IN_USE", "the code was redeemed", "55000")}
  end if;
  delete from ${codes} x where x.${k("id")} = delete_promotion_code.code;
  return true;
end;
$$;
${userGrant(`${fn("delete_promotion_code")}(uuid)`)}

-- Puts a code on the caller's open cart. Whether it applies (minimum
-- subtotal, products, stacking) shows when the cart is priced.
create or replace function ${fn("apply_promotion_code")}(cart uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_code record;
begin
  select x.${c("tenant")} as tenant, x.${c("user")} as owner, x.${c("status")} as status
  into v_cart from ${orders.table("carts")} x where x.${c("id")} = apply_promotion_code.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    ${fail("ORDERS_CART_NOT_FOUND", "cart not found", "P0002")}
  end if;
  if v_cart.status <> 'open' then
    ${fail("ORDERS_CART_CLOSED", "the cart is no longer open", "55000")}
  end if;
  select k.${k("id")} as id, k.${k("code")} as code, k.${k("promotion")} as promotion,
    k.${k("usageLimit")} as code_limit, k.${k("redemptions")} as code_used,
    x.${p("usageLimit")} as usage_limit, x.${p("redemptions")} as used
  into v_code
  from ${codes} k join ${ctx.table("promotions")} x on x.${p("id")} = k.${k("promotion")}
  where k.${k("tenant")} = v_cart.tenant and k.${k("code")} = ${normalized("apply_promotion_code.code")}
    and x.${p("active")} and (x.${p("startsAt")} is null or x.${p("startsAt")} <= now())
    and (x.${p("endsAt")} is null or x.${p("endsAt")} > now());
  if not found then
    ${fail("PROMOTIONS_CODE_INVALID", "this code is unknown or no longer valid", "P0002")}
  end if;
  if (v_code.code_limit is not null and v_code.code_used >= v_code.code_limit)
    or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
    ${fail("PROMOTIONS_LIMIT_REACHED", "this code was used up", "55000")}
  end if;
  if (select count(*) from ${ctx.table("cartCodes")} x where x.${cc("cart")} = apply_promotion_code.cart and x.${cc("code")} <> v_code.id) >= ${MAX_CART_CODES} then
    ${fail("PROMOTIONS_TOO_MANY_CODES", `a cart holds up to ${MAX_CART_CODES} codes`, "55000")}
  end if;
  insert into ${ctx.table("cartCodes")} (${cc("tenant")}, ${cc("cart")}, ${cc("code")})
  values (v_cart.tenant, apply_promotion_code.cart, v_code.id)
  on conflict do nothing;
  return jsonb_build_object('codeId', v_code.id, 'code', v_code.code, 'promotionId', v_code.promotion);
end;
$$;
${userGrant(`${fn("apply_promotion_code")}(uuid, text)`)}

create or replace function ${fn("remove_promotion_code")}(cart uuid, code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  select x.${c("user")} as owner, x.${c("status")} as status
  into v_cart from ${orders.table("carts")} x where x.${c("id")} = remove_promotion_code.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    ${fail("ORDERS_CART_NOT_FOUND", "cart not found", "P0002")}
  end if;
  if v_cart.status <> 'open' then
    ${fail("ORDERS_CART_CLOSED", "the cart is no longer open", "55000")}
  end if;
  delete from ${ctx.table("cartCodes")} x
  where x.${cc("cart")} = remove_promotion_code.cart
    and x.${cc("code")} in (select k.${k("id")} from ${codes} k where k.${k("code")} = ${normalized("remove_promotion_code.code")});
  return found;
end;
$$;
${userGrant(`${fn("remove_promotion_code")}(uuid, text)`)}
`;
}

/** The SQL condition that product `product` falls in promotion `v_promo`'s scope. */
function scopeCheck(ctx: ModuleContext, product: string): string {
  const catalog = ctx.of("catalog");
  const parts = [
    "v_promo.scope = 'order'",
    `(v_promo.scope = 'products' and ${product} = any (v_promo.targets))`,
  ];
  if (catalog.hasTable("categories") && catalog.hasTable("productCategories")) {
    const cat = columns(catalog, "categories");
    const pc = columns(catalog, "productCategories");
    parts.push(`(v_promo.scope = 'categories' and exists (
      with recursive d (id) as (
        select unnest(v_promo.targets)
        union
        select x.${cat("id")} from ${catalog.table("categories")} x join d on x.${cat("parent")} = d.id
      )
      select 1 from ${catalog.table("productCategories")} y where y.${pc("product")} = ${product} and y.${pc("category")} in (select id from d)
    ))`);
  }
  if (catalog.hasTable("collectionProducts")) {
    const cp = columns(catalog, "collectionProducts");
    parts.push(
      `(v_promo.scope = 'collections' and exists (select 1 from ${catalog.table("collectionProducts")} y where y.${cp("product")} = ${product} and y.${cp("collection")} = any (v_promo.targets)))`,
    );
  }
  return parts.join("\n      or ");
}

export function discountFunctions(
  ctx: ModuleContext,
  names: PromotionsNames,
): string {
  const { fn } = names;
  const orders = ctx.of("orders");
  const p = columns(ctx, "promotions");
  const k = columns(ctx, "codes");
  const cc = columns(ctx, "cartCodes");
  const r = columns(ctx, "redemptions");
  const c = columns(orders, "carts");
  const o = columns(orders, "orders");
  const promotions = ctx.table("promotions");
  const codes = ctx.table("codes");
  const redemptions = ctx.table("redemptions");
  const customerUses = (
    promotion: string,
    customer: string,
    email: string,
  ): string =>
    `(select count(*) from ${redemptions} y where y.${r("promotion")} = ${promotion} and y.${r("status")} = 'redeemed'
      and (y.${r("customer")} = ${customer} or (${email} is not null and lower(y.${r("email")}) = lower(${email}))))`;
  return `
-- Rounds half to even, like money everywhere else in the commerce blocks.
create or replace function ${fn("round_half_even")}(p_value numeric)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value - floor(p_value) > 0.5 then floor(p_value)::bigint + 1
    when p_value - floor(p_value) < 0.5 then floor(p_value)::bigint
    when floor(p_value)::bigint % 2 = 0 then floor(p_value)::bigint
    else floor(p_value)::bigint + 1
  end
$$;
revoke execute on function ${fn("round_half_even")}(numeric) from public, anon, authenticated;

-- The cart's discounts: lines maps a line id to its discount, applied
-- lists the promotions in the order they applied, and problems the codes
-- that don't apply. Promotions run by priority (highest first); a
-- promotion that isn't stackable never combines with another. p_lines
-- are the priced lines (id, productId, subtotal as text). Internal: the
-- orders cart_totals calls it.
create or replace function ${fn("cart_discounts")}(p_cart uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_promo record;
  v_reason text;
  v_eligible text[];
  v_base bigint;
  v_rem jsonb;
  v_disc jsonb := '{}';
  v_applied jsonb := '[]';
  v_problems jsonb := '[]';
  v_free boolean := false;
  v_stackable boolean := true;
  v_amount bigint;
  v_left bigint;
  v_share bigint;
  v_line_rem bigint;
  v_id text;
begin
  select x.${c("tenant")} as tenant, x.${c("user")} as owner, x.${c("currency")} as currency, x.${c("email")} as email
  into v_cart from ${orders.table("carts")} x where x.${c("id")} = p_cart;
  select coalesce(jsonb_object_agg(e ->> 'id', (e ->> 'subtotal')::bigint), '{}') into v_rem
  from jsonb_array_elements(p_lines) e;
  for v_promo in
    select x.${p("id")} as id, x.${p("name")} as name, x.${p("kind")} as kind, x.${p("percent")} as percent,
      x.${p("currency")} as currency, x.${p("amount")} as amount, x.${p("minSubtotal")} as min_subtotal,
      x.${p("scope")} as scope, x.${p("targets")} as targets, x.${p("usageLimit")} as usage_limit,
      x.${p("perCustomerLimit")} as per_customer_limit, x.${p("redemptions")} as used, x.${p("stackable")} as stackable,
      x.${p("automatic")} as automatic,
      (x.${p("active")} and (x.${p("startsAt")} is null or x.${p("startsAt")} <= now())
        and (x.${p("endsAt")} is null or x.${p("endsAt")} > now())) as live,
      code.id as code_id, code.code as code, code.usage_limit as code_limit, code.used as code_used
    from ${promotions} x
    left join lateral (
      select k.${k("id")} as id, k.${k("code")} as code, k.${k("usageLimit")} as usage_limit, k.${k("redemptions")} as used
      from ${ctx.table("cartCodes")} y join ${codes} k on k.${k("id")} = y.${cc("code")}
      where y.${cc("cart")} = p_cart and k.${k("promotion")} = x.${p("id")}
      order by y.${cc("createdAt")}, k.${k("id")}
      limit 1
    ) code on true
    where x.${p("tenant")} = v_cart.tenant and (code.id is not null or (x.${p("automatic")} and x.${p("active")}))
    order by x.${p("priority")} desc, x.${p("createdAt")}, x.${p("id")}
  loop
    v_reason := null;
    if not v_promo.live then
      v_reason := 'expired';
    elsif (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.code_limit is not null and v_promo.code_used >= v_promo.code_limit)
      or (v_promo.per_customer_limit is not null
        and ${customerUses("v_promo.id", "v_cart.owner", "v_cart.email")} >= v_promo.per_customer_limit) then
      v_reason := 'limit_reached';
    elsif v_promo.currency is not null and v_promo.currency <> v_cart.currency then
      v_reason := 'currency';
    else
      select coalesce(array_agg(e ->> 'id' order by n), '{}'), coalesce(sum((e ->> 'subtotal')::bigint), 0)
      into v_eligible, v_base
      from jsonb_array_elements(p_lines) with ordinality as l(e, n)
      where ${scopeCheck(ctx, "(e ->> 'productId')::uuid")};
      if cardinality(v_eligible) = 0 then
        v_reason := 'not_applicable';
      elsif v_promo.min_subtotal is not null and v_base < v_promo.min_subtotal then
        v_reason := 'min_subtotal';
      elsif jsonb_array_length(v_applied) > 0 and not (v_stackable and v_promo.stackable) then
        v_reason := 'not_combinable';
      end if;
    end if;
    if v_reason is not null then
      if v_promo.code_id is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'promotion_unavailable',
          'promotionId', v_promo.id, 'code', v_promo.code, 'reason', v_reason));
      end if;
      continue;
    end if;
    v_amount := 0;
    if v_promo.kind = 'percentage' then
      foreach v_id in array v_eligible loop
        v_line_rem := (v_rem ->> v_id)::bigint;
        v_share := least(${fn("round_half_even")}(v_line_rem * v_promo.percent / 100), v_line_rem);
        v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
        v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
        v_amount := v_amount + v_share;
      end loop;
    elsif v_promo.kind = 'fixed' then
      select coalesce(sum((v_rem ->> e)::bigint), 0) into v_base from unnest(v_eligible) e;
      v_left := least(v_promo.amount, v_base);
      if v_base > 0 then
        foreach v_id in array v_eligible loop
          v_line_rem := (v_rem ->> v_id)::bigint;
          v_share := floor(least(v_promo.amount, v_base)::numeric * v_line_rem / v_base)::bigint;
          v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
          v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
          v_left := v_left - v_share;
        end loop;
        foreach v_id in array v_eligible loop
          exit when v_left = 0;
          if (v_rem ->> v_id)::bigint > 0 then
            v_rem := jsonb_set(v_rem, array[v_id], to_jsonb((v_rem ->> v_id)::bigint - 1));
            v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + 1));
            v_left := v_left - 1;
          end if;
        end loop;
        v_amount := least(v_promo.amount, v_base);
      end if;
    else
      v_free := true;
    end if;
    v_stackable := v_stackable and v_promo.stackable;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('promotionId', v_promo.id, 'name', v_promo.name,
      'kind', v_promo.kind, 'codeId', v_promo.code_id, 'code', v_promo.code, 'amount', v_amount::text));
  end loop;
  select coalesce(jsonb_object_agg(key, value #>> '{}'), '{}') into v_disc from jsonb_each(v_disc);
  return jsonb_build_object('lines', v_disc, 'applied', v_applied, 'freeShipping', v_free, 'problems', v_problems);
end;
$$;
revoke execute on function ${fn("cart_discounts")}(uuid, jsonb) from public, anon, authenticated;

-- Records the order's promotions inside checkout. The promotion row lock
-- keeps usage limits under concurrent checkouts; a limit reached since the
-- cart was priced fails the checkout (PROMOTIONS_LIMIT_REACHED).
-- Internal: the orders place_order calls it.
create or replace function ${fn("redeem_promotions")}(p_order uuid, p_applied jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_entry jsonb;
  v_promo record;
  v_code record;
  v_id uuid;
  v_count integer := 0;
begin
  select x.${o("id")} as id, x.${o("tenant")} as tenant, x.${o("customer")} as customer, x.${o("email")} as email,
    x.${o("currency")} as currency
  into v_order from ${orders.table("orders")} x where x.${o("id")} = p_order;
  for v_entry in select e from jsonb_array_elements(coalesce(p_applied, '[]'::jsonb)) e loop
    select x.${p("id")} as id, x.${p("usageLimit")} as usage_limit, x.${p("perCustomerLimit")} as per_customer_limit,
      x.${p("redemptions")} as used
    into v_promo from ${promotions} x where x.${p("id")} = (v_entry ->> 'promotionId')::uuid for update;
    if not found or (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.per_customer_limit is not null
        and ${customerUses("v_promo.id", "v_order.customer", "v_order.email")} >= v_promo.per_customer_limit) then
      ${fail("PROMOTIONS_LIMIT_REACHED", "a promotion on this cart reached its usage limit", "55000")}
    end if;
    if v_entry ->> 'codeId' is not null then
      select x.${k("usageLimit")} as usage_limit, x.${k("redemptions")} as used
      into v_code from ${codes} x where x.${k("id")} = (v_entry ->> 'codeId')::uuid for update;
      if not found or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
        ${fail("PROMOTIONS_LIMIT_REACHED", "a code on this cart was used up", "55000")}
      end if;
      update ${codes} x set ${k("redemptions")} = x.${k("redemptions")} + 1 where x.${k("id")} = (v_entry ->> 'codeId')::uuid;
    end if;
    update ${promotions} x set ${p("redemptions")} = x.${p("redemptions")} + 1 where x.${p("id")} = v_promo.id;
    insert into ${redemptions} (${r("tenant")}, ${r("promotion")}, ${r("code")}, ${r("order")}, ${r("customer")},
      ${r("email")}, ${r("currency")}, ${r("amount")})
    values (v_order.tenant, v_promo.id, (v_entry ->> 'codeId')::uuid, v_order.id, v_order.customer, v_order.email,
      v_order.currency, (v_entry ->> 'amount')::bigint)
    returning ${r("id")} into v_id;
    ${ctx.record({
      type: "promotion.redeemed",
      payload: `jsonb_build_object('organizationId', v_order.tenant, 'id', v_id, 'promotionId', v_promo.id, 'code', v_entry ->> 'code', 'orderId', v_order.id, 'currency', v_order.currency, 'amount', v_entry ->> 'amount')`,
      subject: "'promotion-redemptions/' || v_id::text",
      tenant: "v_order.tenant",
      audit: false,
    })}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function ${fn("redeem_promotions")}(uuid, jsonb) from public, anon, authenticated;

-- Gives a cancelled order's redemptions back to their limits. Internal:
-- the orders cancel_order and expire_orders call it.
create or replace function ${fn("release_promotions")}(p_order uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    update ${redemptions} x set ${r("status")} = 'released', ${r("releasedAt")} = now()
    where x.${r("order")} = p_order and x.${r("status")} = 'redeemed'
    returning x.${r("promotion")} as promotion, x.${r("code")} as code
  loop
    update ${promotions} x set ${p("redemptions")} = greatest(x.${p("redemptions")} - 1, 0) where x.${p("id")} = v_row.promotion;
    if v_row.code is not null then
      update ${codes} x set ${k("redemptions")} = greatest(x.${k("redemptions")} - 1, 0) where x.${k("id")} = v_row.code;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function ${fn("release_promotions")}(uuid) from public, anon, authenticated;

-- Moves the codes of a cart merged into another, up to what a cart
-- holds. Internal: the orders merge_carts calls it.
create or replace function ${fn("move_cart_codes")}(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into ${ctx.table("cartCodes")} (${cc("tenant")}, ${cc("cart")}, ${cc("code")})
  select x.${cc("tenant")}, p_to, x.${cc("code")}
  from ${ctx.table("cartCodes")} x
  where x.${cc("cart")} = p_from
    and not exists (select 1 from ${ctx.table("cartCodes")} y where y.${cc("cart")} = p_to and y.${cc("code")} = x.${cc("code")})
  order by x.${cc("createdAt")}
  limit greatest(${MAX_CART_CODES} - (select count(*) from ${ctx.table("cartCodes")} y where y.${cc("cart")} = p_to), 0);
  get diagnostics v_count = row_count;
  delete from ${ctx.table("cartCodes")} x where x.${cc("cart")} = p_from;
  return v_count;
end;
$$;
revoke execute on function ${fn("move_cart_codes")}(uuid, uuid) from public, anon, authenticated;
`;
}
