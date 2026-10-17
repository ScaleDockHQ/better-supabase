import type { ModuleContext } from "../context.ts";

import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { type Names, SLUG, amountOf, guard } from "./catalog-functions.ts";

export function priceFunctions(ctx: ModuleContext, names: Names): string {
  const { fn } = names;
  const variants = ctx.table("variants");
  const prices = ctx.table("prices");
  const v = (column: string): string => ctx.col("variants", column);
  const pr = (column: string): string => ctx.col("prices", column);
  const lists = ctx.hasTable("priceLists") && ctx.has("prices", "priceList");
  const compare = ctx.has("prices", "compareAt");

  const validity =
    ctx.has("prices", "validFrom") && ctx.has("prices", "validUntil");

  const listMatch = (alias: string, value: string): string =>
    lists
      ? `${alias}.${pr("priceList")} is not distinct from ${value}`
      : "true";

  const range = (from: string, until: string): string =>
    `tstzrange(coalesce(${from}, '-infinity'::timestamptz), coalesce(${until}, 'infinity'::timestamptz), '[)')`;

  const priceLists = lists ? ctx.table("priceLists") : "";
  const pl = (column: string): string => ctx.col("priceLists", column);

  const listFunctions = lists
    ? `
-- Creates a price list (price_list null) or renames one. customer_group
-- names the customers it is for, such as a B2B tier.
create or replace function ${fn("save_price_list")}(tenant ${ctx.idType}, price_list uuid, name text, customer_group text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_price_list.price_list;
begin
  ${guard(names, "save_price_list.tenant")}
  begin
    if v_id is null then
      insert into ${priceLists} (${pl("tenant")}, ${pl("name")}, ${pl("customerGroup")})
      values (save_price_list.tenant, save_price_list.name, save_price_list.customer_group)
      returning ${pl("id")} into v_id;
    else
      update ${priceLists} x set ${pl("name")} = save_price_list.name, ${pl("customerGroup")} = save_price_list.customer_group
      where x.${pl("id")} = v_id and x.${pl("tenant")} = save_price_list.tenant;
      if not found then
        ${fail("CATALOG_PRICE_LIST_NOT_FOUND", "price list not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_PRICE_LIST_TAKEN", "another price list has this name", "23505")}
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("save_price_list")}(${ctx.idType}, uuid, text, text)`)}

-- Deletes a price list and its prices.
create or replace function ${fn("delete_price_list")}(price_list uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${pl("tenant")} into v_tenant from ${priceLists} x where x.${pl("id")} = delete_price_list.price_list;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${priceLists} x where x.${pl("id")} = delete_price_list.price_list;
  return true;
end;
$$;
${userGrant(`${fn("delete_price_list")}(uuid)`)}
`
    : "";

  return `${listFunctions}
-- Sets a variant's price in a currency, in minor units, for a price list
-- (null for the base price) and a validity window. The same window is
-- updated in place; a window that overlaps another price is refused.
create or replace function ${fn("set_price")}(variant uuid, currency text, amount text, compare_at text, price_list uuid, valid_from timestamptz, valid_until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_amount bigint := ${amountOf("set_price.amount")};
  v_compare bigint := ${amountOf("set_price.compare_at")};
  v_id uuid;
  v_previous bigint;
begin
  select x.${v("tenant")} into v_tenant from ${variants} x where x.${v("id")} = set_price.variant for update;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if ${fn("currency_minor_units")}(set_price.currency) is null then
    ${fail("CATALOG_CURRENCY_INVALID", "not an ISO 4217 currency code", "22023")}
  end if;
  if v_amount is null then
    ${fail("CATALOG_AMOUNT_INVALID", "the amount must be a whole number of minor units", "22023")}
  end if;
  if set_price.compare_at is not null and (v_compare is null or v_compare <= v_amount) then
    ${fail("CATALOG_COMPARE_AT_INVALID", "the compare-at amount must be above the amount", "22023")}
  end if;
  if set_price.valid_until is not null and set_price.valid_until <= coalesce(set_price.valid_from, '-infinity'::timestamptz) then
    ${fail("CATALOG_VALIDITY_INVALID", "valid_until must be after valid_from", "22023")}
  end if;
${
  lists
    ? ""
    : `  if set_price.price_list is not null then
    ${fail("CATALOG_PRICE_LIST_NOT_FOUND", "this catalog has no price lists", "P0002")}
  end if;
`
}${
    compare
      ? ""
      : `  if set_price.compare_at is not null then
    ${fail("CATALOG_COMPARE_AT_INVALID", "this catalog has no compare-at amounts", "22023")}
  end if;
`
  }${
    validity
      ? ""
      : `  if set_price.valid_from is not null or set_price.valid_until is not null then
    ${fail("CATALOG_VALIDITY_INVALID", "this catalog has no validity windows", "22023")}
  end if;
`
  }${
    lists
      ? `  if set_price.price_list is not null and not exists (select 1 from ${priceLists} x where x.${pl("id")} = set_price.price_list and x.${pl("tenant")} = v_tenant) then
    ${fail("CATALOG_PRICE_LIST_NOT_FOUND", "price list not found", "P0002")}
  end if;
`
      : ""
  }  ${ctx.hook("before_price_set", [
    ["uuid", "set_price.variant"],
    ["text", "set_price.currency"],
    ["bigint", "v_amount"],
    ["uuid", "set_price.price_list"],
  ])}
  select x.${pr("id")}, x.${pr("amount")} into v_id, v_previous from ${prices} x
  where x.${pr("variant")} = set_price.variant and x.${pr("currency")} = set_price.currency and ${listMatch("x", "set_price.price_list")}${
    validity
      ? `
    and x.${pr("validFrom")} is not distinct from set_price.valid_from and x.${pr("validUntil")} is not distinct from set_price.valid_until`
      : ""
  };
${
  validity
    ? `  if exists (
    select 1 from ${prices} x
    where x.${pr("variant")} = set_price.variant and x.${pr("currency")} = set_price.currency and ${listMatch("x", "set_price.price_list")}
      and x.${pr("id")} is distinct from v_id
      and ${range(`x.${pr("validFrom")}`, `x.${pr("validUntil")}`)} && ${range("set_price.valid_from", "set_price.valid_until")}
  ) then
    ${fail("CATALOG_PRICE_OVERLAP", "another price of this variant, currency and list covers part of this window", "23P01")}
  end if;
`
    : ""
}  if v_id is null then
    insert into ${prices} (${pr("tenant")}, ${pr("variant")}, ${pr("currency")}, ${pr("amount")}${lists ? `, ${pr("priceList")}` : ""}${compare ? `, ${pr("compareAt")}` : ""}${validity ? `, ${pr("validFrom")}, ${pr("validUntil")}` : ""})
    values (v_tenant, set_price.variant, set_price.currency, v_amount${lists ? ", set_price.price_list" : ""}${compare ? ", v_compare" : ""}${validity ? ", set_price.valid_from, set_price.valid_until" : ""})
    returning ${pr("id")} into v_id;
  else
    update ${prices} x set ${pr("amount")} = v_amount${compare ? `, ${pr("compareAt")} = v_compare` : ""}, ${pr("updatedAt")} = now()
    where x.${pr("id")} = v_id;
  end if;
  if v_previous is distinct from v_amount then
    ${ctx.record({
      type: "catalog.price_changed",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'variantId', set_price.variant, 'priceListId', set_price.price_list, 'currency', set_price.currency, 'amount', v_amount::text, 'previousAmount', v_previous::text)`,
      subject: `'prices/' || v_id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  ${ctx.hook("after_price_set", [
    ["uuid", "v_id"],
    ["bigint", "v_previous"],
  ])}
  return jsonb_build_object('id', v_id, 'amount', v_amount::text, 'previousAmount', v_previous::text);
end;
$$;
${userGrant(`${fn("set_price")}(uuid, text, text, text, uuid, timestamptz, timestamptz)`)}

-- Deletes a price.
create or replace function ${fn("delete_price")}(price uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${pr("tenant")} into v_tenant from ${prices} x where x.${pr("id")} = delete_price.price;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${prices} x where x.${pr("id")} = delete_price.price;
  return true;
end;
$$;
${userGrant(`${fn("delete_price")}(uuid)`)}

-- The price a variant sells at in a currency at a time: the price list's
-- price when it has one, otherwise the base price. Runs as the caller, so
-- the read policies decide which prices it sees. Amounts are text: JSON
-- numbers lose bigint precision.
create or replace function ${fn("variant_price")}(variant uuid, currency text, price_list uuid default null, as_of timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x.${pr("id")},
    'variantId', x.${pr("variant")},
    'currency', x.${pr("currency")},
    'amount', x.${pr("amount")}::text,
    'compareAt', ${compare ? `x.${pr("compareAt")}::text` : "null"},
    'priceListId', ${lists ? `x.${pr("priceList")}` : "null"}
  )
  from ${prices} x
  where x.${pr("variant")} = $1 and x.${pr("currency")} = $2
    and ${lists ? `(x.${pr("priceList")} is null or x.${pr("priceList")} = $3)` : "true"}${
      validity
        ? `
    and ${range(`x.${pr("validFrom")}`, `x.${pr("validUntil")}`)} @> coalesce($4, now())`
        : ""
    }
  order by ${lists ? `(x.${pr("priceList")} is null), ` : ""}x.${pr("updatedAt")} desc
  limit 1
$$;
grant execute on function ${fn("variant_price")}(uuid, text, uuid, timestamptz) to anon, authenticated, service_role;
`;
}

export function categoryFunctions(ctx: ModuleContext, names: Names): string {
  if (!ctx.hasTable("categories")) {
    return "";
  }

  const { fn } = names;
  const categories = ctx.table("categories");
  const k = (column: string): string => ctx.col("categories", column);

  const links = ctx.hasTable("productCategories")
    ? (() => {
        const productCategories = ctx.table("productCategories");
        const products = ctx.table("products");
        const p = (column: string): string => ctx.col("products", column);

        const pc = (column: string): string =>
          ctx.col("productCategories", column);

        return `
-- Replaces the categories a product is filed under.
create or replace function ${fn("set_product_categories")}(product uuid, categories uuid[])
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = set_product_categories.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if exists (
    select 1 from unnest(coalesce(set_product_categories.categories, '{}'::uuid[])) c
    where not exists (select 1 from ${categories} x where x.${k("id")} = c and x.${k("tenant")} = v_tenant)
  ) then
    ${fail("CATALOG_CATEGORY_NOT_FOUND", "category not found", "P0002")}
  end if;
  delete from ${productCategories} x
  where x.${pc("product")} = set_product_categories.product
    and not (x.${pc("category")} = any (coalesce(set_product_categories.categories, '{}'::uuid[])));
  insert into ${productCategories} (${pc("tenant")}, ${pc("product")}, ${pc("category")})
  select distinct v_tenant, set_product_categories.product, c from unnest(coalesce(set_product_categories.categories, '{}'::uuid[])) c
  on conflict do nothing;
  return true;
end;
$$;
${userGrant(`${fn("set_product_categories")}(uuid, uuid[])`)}
`;
      })()
    : "";

  const cycle = (
    category: string,
    parent: string,
  ): string => `if ${parent} is not null and exists (
    with recursive up (id) as (
      select ${parent}
      union
      select x.${k("parent")} from ${categories} x join up on x.${k("id")} = up.id where x.${k("parent")} is not null
    )
    select 1 from up where up.id = ${category}
  ) then
    ${fail("CATALOG_CATEGORY_CYCLE", "a category can't sit under itself", "22023")}
  end if;`;

  return `
-- Creates a category (category null) or updates one, under parent (null
-- for the top level). A new category goes after its siblings.
create or replace function ${fn("save_category")}(tenant ${ctx.idType}, category uuid, parent uuid, name text, slug text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_category.category;
  v_slug text := coalesce(nullif(save_category.slug, ''), trim(both '-' from regexp_replace(lower(save_category.name), '[^a-z0-9]+', '-', 'g')));
  v_last text;
  v_rank text;
begin
  ${guard(names, "save_category.tenant")}
  if v_slug is null or v_slug !~ ${SLUG} then
    ${fail("CATALOG_SLUG_INVALID", "the slug must be lower-case letters, digits and hyphens", "22023")}
  end if;
  if save_category.parent is not null and not exists (select 1 from ${categories} x where x.${k("id")} = save_category.parent and x.${k("tenant")} = save_category.tenant) then
    ${fail("CATALOG_CATEGORY_NOT_FOUND", "parent category not found", "P0002")}
  end if;
  ${cycle("v_id", "save_category.parent")}
  begin
    if v_id is null then
      select max(x.${k("rank")} collate "C") into v_last from ${categories} x
      where x.${k("tenant")} = save_category.tenant and x.${k("parent")} is not distinct from save_category.parent;
      v_rank := ${rankAfter("v_last")};
      insert into ${categories} (${k("tenant")}, ${k("parent")}, ${k("name")}, ${k("slug")}, ${k("description")}, ${k("rank")})
      values (save_category.tenant, save_category.parent, save_category.name, v_slug, save_category.description, v_rank)
      returning ${k("id")} into v_id;
    else
      update ${categories} x set ${k("parent")} = save_category.parent, ${k("name")} = save_category.name, ${k("slug")} = v_slug,
        ${k("description")} = save_category.description, ${k("updatedAt")} = now()
      where x.${k("id")} = v_id and x.${k("tenant")} = save_category.tenant
      returning x.${k("rank")} into v_rank;
      if not found then
        ${fail("CATALOG_CATEGORY_NOT_FOUND", "category not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_SLUG_TAKEN", "another category has this slug", "23505")}
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
${userGrant(`${fn("save_category")}(${ctx.idType}, uuid, uuid, text, text, text)`)}

-- Moves a category under parent (null for the top level) at rank, a key
-- from rankBetween over its new siblings' keys.
create or replace function ${fn("move_category")}(category uuid, parent uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  if move_category.rank is null or move_category.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("CATALOG_RANK_INVALID", "not a rank key", "22023")}
  end if;
  select x.${k("tenant")} into v_tenant from ${categories} x where x.${k("id")} = move_category.category for update;
  if v_tenant is null then
    ${fail("CATALOG_CATEGORY_NOT_FOUND", "category not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if move_category.parent is not null and not exists (select 1 from ${categories} x where x.${k("id")} = move_category.parent and x.${k("tenant")} = v_tenant) then
    ${fail("CATALOG_CATEGORY_NOT_FOUND", "parent category not found", "P0002")}
  end if;
  ${cycle("move_category.category", "move_category.parent")}
  update ${categories} x set ${k("parent")} = move_category.parent, ${k("rank")} = move_category.rank, ${k("updatedAt")} = now()
  where x.${k("id")} = move_category.category;
  return true;
end;
$$;
${userGrant(`${fn("move_category")}(uuid, uuid, text)`)}

-- Deletes a category without subcategories; products leave it.
create or replace function ${fn("delete_category")}(category uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${k("tenant")} into v_tenant from ${categories} x where x.${k("id")} = delete_category.category;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  begin
    delete from ${categories} x where x.${k("id")} = delete_category.category;
  exception when foreign_key_violation then
    ${fail("CATALOG_CATEGORY_HAS_CHILDREN", "move or delete the subcategories first", "23503")}
  end;
  return true;
end;
$$;
${userGrant(`${fn("delete_category")}(uuid)`)}
${links}`;
}

export function collectionFunctions(ctx: ModuleContext, names: Names): string {
  if (!ctx.hasTable("collections")) {
    return "";
  }

  const { fn } = names;
  const collections = ctx.table("collections");
  const k = (column: string): string => ctx.col("collections", column);

  const members = ctx.hasTable("collectionProducts")
    ? (() => {
        const entries = ctx.table("collectionProducts");
        const products = ctx.table("products");
        const p = (column: string): string => ctx.col("products", column);

        const e = (column: string): string =>
          ctx.col("collectionProducts", column);

        return `
-- Adds a product to a manual collection at rank (null to append), or moves
-- it there. Returns its rank key.
create or replace function ${fn("add_to_collection")}(collection uuid, product uuid, rank text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_kind text;
  v_last text;
  v_rank text := add_to_collection.rank;
begin
  select x.${k("tenant")}, x.${k("kind")} into v_tenant, v_kind from ${collections} x where x.${k("id")} = add_to_collection.collection for update;
  if v_tenant is null then
    ${fail("CATALOG_COLLECTION_NOT_FOUND", "collection not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if v_kind <> 'manual' then
    ${fail("CATALOG_COLLECTION_RULE", "a rule collection picks its products from its rule", "22023")}
  end if;
  if not exists (select 1 from ${products} x where x.${p("id")} = add_to_collection.product and x.${p("tenant")} = v_tenant) then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  if v_rank is not null and v_rank !~ ${RANK_KEY_PATTERN} then
    ${fail("CATALOG_RANK_INVALID", "not a rank key", "22023")}
  end if;
  if v_rank is null then
    select max(x.${e("rank")} collate "C") into v_last from ${entries} x where x.${e("collection")} = add_to_collection.collection;
    v_rank := ${rankAfter("v_last")};
  end if;
  insert into ${entries} as x (${e("tenant")}, ${e("collection")}, ${e("product")}, ${e("rank")})
  values (v_tenant, add_to_collection.collection, add_to_collection.product, v_rank)
  on conflict (${e("collection")}, ${e("product")}) do update set ${e("rank")} = excluded.${e("rank")};
  return v_rank;
end;
$$;
${userGrant(`${fn("add_to_collection")}(uuid, uuid, text)`)}

-- Removes a product from a manual collection.
create or replace function ${fn("remove_from_collection")}(collection uuid, product uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${k("tenant")} into v_tenant from ${collections} x where x.${k("id")} = remove_from_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${entries} x where x.${e("collection")} = remove_from_collection.collection and x.${e("product")} = remove_from_collection.product;
  return found;
end;
$$;
${userGrant(`${fn("remove_from_collection")}(uuid, uuid)`)}
`;
      })()
    : "";

  return `
-- Creates a collection (collection null) or updates one. A manual
-- collection lists ranked products; a rule collection stores a filter tree
-- (a FilterQuery group) that picks them.
create or replace function ${fn("save_collection")}(tenant ${ctx.idType}, collection uuid, title text, slug text, kind text, rule jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_collection.collection;
  v_kind text := coalesce(save_collection.kind, 'manual');
  v_slug text := coalesce(nullif(save_collection.slug, ''), trim(both '-' from regexp_replace(lower(save_collection.title), '[^a-z0-9]+', '-', 'g')));
begin
  ${guard(names, "save_collection.tenant")}
  if v_slug is null or v_slug !~ ${SLUG} then
    ${fail("CATALOG_SLUG_INVALID", "the slug must be lower-case letters, digits and hyphens", "22023")}
  end if;
  if v_kind not in ('manual', 'rule') then
    ${fail("CATALOG_COLLECTION_KIND", "the kind must be manual or rule", "22023")}
  end if;
  if (v_kind = 'rule') <> (save_collection.rule is not null) then
    ${fail("CATALOG_COLLECTION_RULE", "a rule collection needs a rule and a manual one none", "22023")}
  end if;
  if v_kind = 'rule' and not (
    jsonb_typeof(save_collection.rule) = 'object'
    and save_collection.rule ->> 'type' = 'group'
    and save_collection.rule ->> 'combinator' in ('and', 'or')
    and jsonb_typeof(save_collection.rule -> 'rules') = 'array'
  ) then
    ${fail("CATALOG_COLLECTION_RULE", "the rule must be a filter group with a combinator and rules", "22023")}
  end if;
  begin
    if v_id is null then
      insert into ${collections} (${k("tenant")}, ${k("title")}, ${k("slug")}, ${k("kind")}, ${k("rule")})
      values (save_collection.tenant, save_collection.title, v_slug, v_kind, save_collection.rule)
      returning ${k("id")} into v_id;
    else
      update ${collections} x set ${k("title")} = save_collection.title, ${k("slug")} = v_slug, ${k("kind")} = v_kind,
        ${k("rule")} = save_collection.rule, ${k("updatedAt")} = now()
      where x.${k("id")} = v_id and x.${k("tenant")} = save_collection.tenant;
      if not found then
        ${fail("CATALOG_COLLECTION_NOT_FOUND", "collection not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_SLUG_TAKEN", "another collection has this slug", "23505")}
  end;${
    ctx.hasTable("collectionProducts")
      ? `
  if v_kind = 'rule' then
    delete from ${ctx.table("collectionProducts")} x where x.${ctx.col("collectionProducts", "collection")} = v_id;
  end if;`
      : ""
  }
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'kind', v_kind);
end;
$$;
${userGrant(`${fn("save_collection")}(${ctx.idType}, uuid, text, text, text, jsonb)`)}

-- Deletes a collection.
create or replace function ${fn("delete_collection")}(collection uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${k("tenant")} into v_tenant from ${collections} x where x.${k("id")} = delete_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${collections} x where x.${k("id")} = delete_collection.collection;
  return true;
end;
$$;
${userGrant(`${fn("delete_collection")}(uuid)`)}
${members}`;
}

export function storefrontFunctions(ctx: ModuleContext, names: Names): string {
  if (!ctx.hasTable("storefronts")) {
    return "";
  }

  const { fn } = names;
  const storefronts = ctx.table("storefronts");
  const products = ctx.table("products");
  const s = (column: string): string => ctx.col("storefronts", column);
  const p = (column: string): string => ctx.col("products", column);

  return `
-- Tenants whose storefront is published. The storefront read policies
-- call it, so it runs as its owner and returns nothing else.
create or replace function ${fn("storefront_tenants")}()
returns setof ${ctx.idType}
language sql
stable
security definer
set search_path = ''
as $$
  select x.${s("tenant")} from ${storefronts} x where x.${s("publishedAt")} is not null
$$;
grant execute on function ${fn("storefront_tenants")}() to anon, authenticated, service_role;

-- Active products of published storefronts, for the storefront policies.
create or replace function ${fn("storefront_products")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x.${p("id")} from ${products} x
  where x.${p("status")} = 'active'
    and x.${p("tenant")} in (select y.${s("tenant")} from ${storefronts} y where y.${s("publishedAt")} is not null)
$$;
grant execute on function ${fn("storefront_products")}() to anon, authenticated, service_role;

-- Publishes or unpublishes a tenant's storefront. With options.storefront
-- "public", anyone can read the active products of a published storefront.
create or replace function ${fn("publish_storefront")}(tenant ${ctx.idType}, published boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${guard(names, "publish_storefront.tenant")}
  insert into ${storefronts} as x (${s("tenant")}, ${s("publishedAt")})
  values (publish_storefront.tenant, case when publish_storefront.published then now() end)
  on conflict (${s("tenant")}) do update
    set ${s("publishedAt")} = case when publish_storefront.published then coalesce(x.${s("publishedAt")}, now()) end;
  if publish_storefront.published then
    ${ctx.record({
      type: "storefront.published",
      payload: `jsonb_build_object('organizationId', publish_storefront.tenant)`,
      subject: `'storefronts/' || publish_storefront.tenant::text`,
      tenant: "publish_storefront.tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "storefront.unpublished",
      payload: `jsonb_build_object('organizationId', publish_storefront.tenant)`,
      subject: `'storefronts/' || publish_storefront.tenant::text`,
      tenant: "publish_storefront.tenant",
      audit: false,
    })}
  end if;
  return publish_storefront.published;
end;
$$;
${userGrant(`${fn("publish_storefront")}(${ctx.idType}, boolean)`)}
`;
}
