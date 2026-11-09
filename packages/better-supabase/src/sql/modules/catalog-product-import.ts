import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { fail, serviceGrant } from "../shared.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** Manufacturer, model and tax code, when the product table has them. */
export function productDetailColumns(
  ctx: BlockSqlContext,
  column: (table: string, logical: string) => string,
): string[] {
  return (["manufacturer", "model", "taxCode"] as const).flatMap((logical) =>
    ctx.has("products", logical) ? [`${column("products", logical)} text`] : [],
  );
}

/** A product import and the category link it can write. */
export function productImportSql(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const fn = (name: string): string => ctx.fn(name);

  const set = (logical: string, expr: string): string =>
    ctx.has("products", logical)
      ? `, ${p(logical)} = coalesce(${expr}, x.${p(logical)})`
      : "";

  const inserted = (logical: string, expr: string): string =>
    ctx.has("products", logical) ? `, ${expr}` : "";

  const insertedCol = (logical: string): string =>
    ctx.has("products", logical) ? `, ${p(logical)}` : "";

  return `
-- One product and its default variant. The price is data.price, then
-- data.listPrice, then the last purchase price times the markup when
-- options.priceFallback is set. A name that is mostly control characters is
-- refused. A sku already used by another product is refused. A taken slug
-- gains the item key.
create or replace function ${fn("import_product")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_product.item -> 'data';
  v_tenant ${ctx.idType} := (import_product.item ->> 'tenant')::${ctx.idType};
  v_raw text := coalesce(v_data ->> 'name', v_data ->> 'title', '');
  v_name text;
  v_slug text;
  v_sku text := nullif(btrim(v_data ->> 'sku'), '');
  v_price bigint;
  v_id uuid := nullif(import_product.subject_id, '')::uuid;
  v_updated timestamptz;
  v_fallback boolean := coalesce((import_product.item -> 'options' ->> 'priceFallback')::boolean, false);
begin
  if length(regexp_replace(v_raw, '[[:cntrl:][:space:]]', '', 'g')) * 2 < length(regexp_replace(coalesce(v_raw, ''), '[[:space:]]', '', 'g')) then
    ${fail("IMPORT_ITEM_INVALID", "a product name is mostly control characters", "22023")}
  end if;
  v_name := btrim(regexp_replace(regexp_replace(v_raw, '[[:cntrl:]]', '', 'g'), U&'[\\+00E000-\\+00F8FF]', '', 'g'));
  if v_name is null or length(v_name) = 0 then
    ${fail("IMPORT_ITEM_INVALID", "a product needs a name", "22023")}
  end if;
  v_price := coalesce(
    nullif(v_data ->> 'price', '')::bigint,
    nullif(v_data ->> 'listPrice', '')::bigint,
    case when v_fallback then round(nullif(v_data ->> 'lastPurchasePrice', '')::numeric * coalesce(nullif(v_data ->> 'markup', '')::numeric, 1))::bigint end);
  v_slug := trim(both '-' from lower(regexp_replace(coalesce(nullif(v_data ->> 'slug', ''), v_name), '[^a-zA-Z0-9]+', '-', 'g')));
  if v_id is not null and exists (
    select 1 from ${products} x
    where x.${p("id")} = v_id and x.${p("tenant")} = v_tenant and x.${p("title")} is not distinct from v_name
      and x.${p("slug")} is not distinct from v_slug
      ${ctx.has("products", "price") ? `and x.${p("price")} is not distinct from coalesce(v_price, x.${p("price")})` : ""}
  ) and (v_sku is null or exists (
    select 1 from ${variants} y where y.${v("product")} = v_id and y.${v("sku")} is not distinct from v_sku
  )) then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', (select x.${p("updatedAt")} from ${products} x where x.${p("id")} = v_id));
  end if;
  if v_sku is not null and exists (
    select 1 from ${variants} y where y.${v("tenant")} = v_tenant and y.${v("sku")} = v_sku and y.${v("product")} is distinct from v_id
  ) then
    ${fail("IMPORT_ITEM_INVALID", "a sku is already used by another product", "22023")}
  end if;
  if exists (select 1 from ${products} x where x.${p("tenant")} = v_tenant and x.${p("slug")} = v_slug and x.${p("id")} is distinct from v_id) then
    v_slug := left(v_slug, 40) || '-' || left(coalesce(import_product.item ->> 'key', 'item'), 8);
  end if;
  if v_id is null then
    insert into ${products} (${p("tenant")}, ${p("title")}, ${p("slug")}${insertedCol("price")}${insertedCol("manufacturer")}${insertedCol("model")}${insertedCol("taxCode")})
    values (v_tenant, v_name, v_slug${inserted("price", "v_price")}${inserted("manufacturer", "nullif(btrim(v_data ->> 'manufacturer'), '')")}${inserted("model", "nullif(btrim(v_data ->> 'model'), '')")}${inserted("taxCode", "nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), '')")})
    returning ${p("id")}, ${p("updatedAt")} into v_id, v_updated;
  else
    update ${products} x set ${p("title")} = v_name, ${p("slug")} = v_slug, ${p("updatedAt")} = now()${set("price", "v_price")}${set("manufacturer", "nullif(btrim(v_data ->> 'manufacturer'), '')")}${set("model", "nullif(btrim(v_data ->> 'model'), '')")}${set("taxCode", "nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), '')")}
    where x.${p("id")} = v_id and x.${p("tenant")} = v_tenant
    returning x.${p("updatedAt")} into v_updated;
  end if;
  if not exists (select 1 from ${variants} y where y.${v("product")} = v_id) then
    insert into ${variants} (${v("tenant")}, ${v("product")}, ${v("sku")}${ctx.has("variants", "barcode") ? `, ${v("barcode")}` : ""}${ctx.has("variants", "price") ? `, ${v("price")}` : ""})
    values (v_tenant, v_id, coalesce(v_sku, v_slug)${ctx.has("variants", "barcode") ? `, nullif(btrim(v_data ->> 'ean'), '')` : ""}${ctx.has("variants", "price") ? ", v_price" : ""});
  elsif v_sku is not null then
    update ${variants} y set ${v("sku")} = v_sku${ctx.has("variants", "barcode") ? `, ${v("barcode")} = coalesce(nullif(btrim(v_data ->> 'ean'), ''), y.${v("barcode")})` : ""}${ctx.has("variants", "price") ? `, ${v("price")} = coalesce(v_price, y.${v("price")})` : ""}
    where y.${v("id")} = (select y2.${v("id")} from ${variants} y2 where y2.${v("product")} = v_id order by y2.${v("createdAt")} limit 1);
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_product")}(uuid, jsonb, text)`)}

create or replace function ${fn("product_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${p("updatedAt")} from ${products} x where x.${p("id")}::text = product_updated_at.subject_id
$$;
${serviceGrant(`${fn("product_updated_at")}(text)`)}
${categoryTarget(ctx)}
`;
}

function categoryTarget(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("productCategories") || !ctx.hasTable("categories")) {
    return "";
  }

  const links = ctx.table("productCategories");
  const categories = ctx.table("categories");
  const l = (column: string): string => ctx.col("productCategories", column);
  const c = (column: string): string => ctx.col("categories", column);
  const fn = (name: string): string => ctx.fn(name);

  return `
create or replace function ${fn("import_product_category")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_product_category.item -> 'data';
  v_product uuid := nullif(coalesce(import_product_category.item -> 'resolved' ->> 'product', v_data ->> 'productId'), '')::uuid;
  v_category uuid := nullif(coalesce(import_product_category.item -> 'resolved' ->> 'category', v_data ->> 'categoryId'), '')::uuid;
begin
  if v_category is null and nullif(btrim(v_data ->> 'name'), '') is not null then
    select x.${c("id")} into v_category from ${categories} x
    where x.${c("tenant")} = (import_product_category.item ->> 'tenant')::${ctx.idType} and x.${c("name")} = btrim(v_data ->> 'name');
  end if;
  if v_product is null or v_category is null then
    ${fail("IMPORT_ITEM_INVALID", "a product category needs a product and a category", "22023")}
  end if;
  insert into ${links} (${l("tenant")}, ${l("product")}, ${l("category")})
  values ((import_product_category.item ->> 'tenant')::${ctx.idType}, v_product, v_category)
  on conflict do nothing;
  return jsonb_build_object('subjectId', v_product::text || ':' || v_category::text, 'updatedAt', now());
end;
$$;
${serviceGrant(`${fn("import_product_category")}(uuid, jsonb, text)`)}

create or replace function ${fn("product_category_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select now()
$$;
${serviceGrant(`${fn("product_category_updated_at")}(text)`)}
`;
}

/** Product and product-category import targets. */
export function productImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (own.mode === "custom") {
    return [];
  }

  return [
    {
      entity: "product",
      subjectType: "product",
      write: plain(own.fn("import_product")),
      updatedAt: plain(own.fn("product_updated_at")),
      refs: { tax: "tax_code" },
    },
    ...(own.hasTable("productCategories")
      ? [
          {
            entity: "product_category",
            subjectType: "product_category",
            write: plain(own.fn("import_product_category")),
            updatedAt: plain(own.fn("product_category_updated_at")),
            refs: { product: "product", category: "category" },
          },
        ]
      : []),
  ];
}
