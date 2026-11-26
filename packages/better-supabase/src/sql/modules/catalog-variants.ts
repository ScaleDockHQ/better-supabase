import type { BlockSqlContext } from "../context.ts";
import type { Names } from "./catalog-names.ts";

import { sqlString } from "../../core/template.ts";
import {
  columnDefaults,
  uniqueViolationOn,
  withColumnDefault,
} from "../column-defaults.ts";
import {
  columnsObject,
  extraFieldsArg,
  fail,
  insertExtraColumns,
  updateExtraColumns,
  userGrant,
} from "../shared.ts";
import {
  guard,
  stockHistoryCheck,
  variantExtras,
} from "./catalog-functions.ts";
import { catalogRank } from "./catalog-names.ts";

export function variantFunctions(ctx: BlockSqlContext, names: Names): string {
  const historyCheck = stockHistoryCheck(ctx);
  const { fn } = names;
  const rank = catalogRank(ctx);
  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const optional = (column: string): boolean => ctx.has("variants", column);
  const extras = variantExtras(ctx);
  const extraArg = extraFieldsArg(extras);

  const oldVariantArgs =
    "uuid, uuid, text, uuid[], text, text, integer, boolean, boolean";

  const variantArgs = `${oldVariantArgs}, text[]`;

  const clearable = ["sku", "title", "barcode", "weight"].filter((column) =>
    ctx.has("variants", column),
  );

  const inserted = insertExtraColumns(
    variants,
    extras,
    "coalesce(upsert_variant.fields, '{}'::jsonb)",
  );

  const tracking = optional("trackInventory")
    ? ""
    : `
  if upsert_variant.track_inventory is not null then
    ${fail("CATALOG_TRACK_INVENTORY_UNSUPPORTED", "this catalog tracks inventory per product, not per variant", "22023")}
  end if;`;

  const retired = (alias: string): string =>
    typeof ctx.config.columns["variants"]?.["status"] === "string" &&
    ctx.has("variants", "status")
      ? ` and ${ctx.is("variants", "status", `${alias}.${v("status")}::text`, ["archived"], true)}`
      : "";

  const hasValues =
    ctx.hasTable("variantValues") &&
    ctx.hasTable("optionValues") &&
    ctx.hasTable("options");

  const columns: readonly (readonly [string, string, string])[] = [
    ["sku", "upsert_variant.sku", "upsert_variant.sku"],
    ...(optional("title")
      ? ([["title", "upsert_variant.title", "upsert_variant.title"]] as const)
      : []),
    ...(optional("barcode")
      ? ([
          ["barcode", "upsert_variant.barcode", "upsert_variant.barcode"],
        ] as const)
      : []),
    ...(optional("weight")
      ? ([
          [
            "weight",
            "upsert_variant.weight_grams",
            "upsert_variant.weight_grams",
          ],
        ] as const)
      : []),
    ...(optional("trackInventory")
      ? ([
          [
            "trackInventory",
            "coalesce(upsert_variant.track_inventory, true)",
            "upsert_variant.track_inventory",
          ],
        ] as const)
      : []),
    [
      "allowBackorder",
      "coalesce(upsert_variant.allow_backorder, false)",
      "upsert_variant.allow_backorder",
    ],
  ];

  const defaulted = columns
    .filter(([column]) => clearable.includes(column))
    .map(([column, value]): readonly [string, string] => [v(column), value]);

  const valueChecks = hasValues
    ? (() => {
        const options = ctx.table("options");
        const optionValues = ctx.table("optionValues");
        const variantValues = ctx.table("variantValues");
        const o = (column: string): string => ctx.col("options", column);
        const ov = (column: string): string => ctx.col("optionValues", column);
        const vv = (column: string): string => ctx.col("variantValues", column);

        return {
          check: `  if v_created or upsert_variant.option_values is not null then
  v_wanted := coalesce((select array_agg(distinct x order by x) from unnest(upsert_variant.option_values) x), '{}'::uuid[]);
  if cardinality(v_wanted) <> coalesce(cardinality(upsert_variant.option_values), 0)
    or exists (
      select 1 from unnest(v_wanted) x
      where not exists (
        select 1 from ${optionValues} ov join ${options} o on o.${o("id")} = ov.${ov("option")}
        where ov.${ov("id")} = x and o.${o("product")} = upsert_variant.product
      )
    )
    or (select count(distinct ov.${ov("option")}) from ${optionValues} ov where ov.${ov("id")} = any (v_wanted)) <> cardinality(v_wanted)
    or (select count(*) from ${options} o where o.${o("product")} = upsert_variant.product) <> cardinality(v_wanted) then
    ${fail("CATALOG_VARIANT_OPTIONS", "a variant needs exactly one value of each product option", "22023")}
  end if;
  if exists (
    select 1 from ${variants} x
    where x.${v("product")} = upsert_variant.product
      and x.${v("id")} is distinct from upsert_variant.variant${retired("x")}
      and coalesce((select array_agg(y.${vv("value")} order by y.${vv("value")}) from ${variantValues} y where y.${vv("variant")} = x.${v("id")}), '{}'::uuid[]) = v_wanted
  ) then
    ${fail("CATALOG_VARIANT_DUPLICATE", "another variant has these option values", "23505")}
  end if;
  end if;`,
          write: `  if v_wanted is not null then
  delete from ${variantValues} x where x.${vv("variant")} = v_id and not (x.${vv("value")} = any (v_wanted));
  insert into ${variantValues} (${vv("tenant")}, ${vv("variant")}, ${vv("value")})
  select v_tenant, v_id, x from unnest(v_wanted) x
  on conflict do nothing;
  end if;`,
        };
      })()
    : {
        check: `  v_wanted := '{}'::uuid[];
  if coalesce(cardinality(upsert_variant.option_values), 0) > 0 then
    ${fail("CATALOG_VARIANT_OPTIONS", "this catalog has no option values", "22023")}
  end if;
  if exists (select 1 from ${variants} x where x.${v("product")} = upsert_variant.product and x.${v("id")} is distinct from upsert_variant.variant) then
    ${fail("CATALOG_VARIANT_DUPLICATE", "a product without options has one variant", "23505")}
  end if;`,
        write: "",
      };

  return `
-- Creates a variant (variant null) or updates one. option_values holds one
-- option value id per product option; no two variants share a combination.
-- On an update a null argument keeps the column and clear names the columns
-- to empty. fields: the extra columns (columns your schema files add) to set.
drop function if exists ${fn("upsert_variant")}(${oldVariantArgs});
drop function if exists ${fn("upsert_variant")}(${oldVariantArgs}, jsonb);
${extraArg.drop(fn("upsert_variant"), variantArgs)}
create or replace function ${fn("upsert_variant")}(product uuid, variant uuid, sku text, option_values uuid[], title text, barcode text, weight_grams integer, track_inventory boolean, allow_backorder boolean, clear text[] default null${extraArg.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_id uuid := upsert_variant.variant;
  v_created boolean := upsert_variant.variant is null;
  v_wanted uuid[];
  v_last text;
  v_rank text;
  v_sku text := upsert_variant.sku;
  v_defaults jsonb;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = upsert_variant.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  if v_created then
    ${guard(names, "v_tenant", names.create)}
  else
    ${guard(names, "v_tenant", names.update)}
  end if;${tracking}
  if exists (select 1 from unnest(coalesce(upsert_variant.clear, '{}'::text[])) c where c <> all (${sqlString(`{${clearable.join(",")}}`)}::text[])) then
    ${fail("CATALOG_CLEAR_INVALID", `clear names only ${clearable.join(", ")}`, "22023")}
  end if;
${valueChecks.check}
  ${ctx.hook("before_variant_save", [
    ["uuid", "upsert_variant.product"],
    ["uuid", "upsert_variant.variant"],
    ["text", "upsert_variant.sku"],
    ["uuid[]", "v_wanted"],
  ])}
  begin
    if v_created then
      select max(${rank.order(`x.${v("rank")}`)}) into v_last from ${variants} x where x.${v("product")} = upsert_variant.product;
      v_rank := ${rank.after("v_last")};
      ${columnDefaults(variants, defaulted, "v_defaults")}
      insert into ${variants} as x (${v("tenant")}, ${v("product")}, ${columns.map(([column]) => v(column)).join(", ")}, ${v("rank")}${inserted.columns})
      values (v_tenant, upsert_variant.product, ${columns.map(([column, value]) => (clearable.includes(column) ? withColumnDefault(variants, v(column), value, "v_defaults") : value)).join(", ")}, ${rank.write("v_rank")}${inserted.values})
      returning x.${v("id")}, x.${v("sku")} into v_id, v_sku;
    else
      update ${variants} x set ${columns.map(([column, , param]) => (clearable.includes(column) ? `${v(column)} = case when ${sqlString(column)} = any (coalesce(upsert_variant.clear, '{}'::text[])) then null else coalesce(${param}, x.${v(column)}) end` : `${v(column)} = coalesce(${param}, x.${v(column)})`)).join(", ")}, ${v("updatedAt")} = now()${updateExtraColumns(variants, extras, "upsert_variant.fields")}
      where x.${v("id")} = upsert_variant.variant and x.${v("product")} = upsert_variant.product
      returning x.${v("rank")}, x.${v("sku")} into v_rank, v_sku;
      if not found then
        ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${uniqueViolationOn(variants, v("sku"), fail("CATALOG_SKU_TAKEN", "another variant has this SKU", "23505"))}
  end;
${valueChecks.write}
  if v_created then
    ${ctx.record({
      type: "product_variant.created",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', upsert_variant.product, 'sku', v_sku)`,
      subject: `'variants/' || v_id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "product_variant.updated",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', upsert_variant.product, 'sku', v_sku)`,
      subject: `'variants/' || v_id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  ${ctx.hook("after_variant_save", [
    ["uuid", "v_id"],
    ["boolean", "v_created"],
  ])}
  return jsonb_build_object('id', v_id, 'sku', v_sku, 'rank', v_rank)${
    extras.length === 0
      ? ""
      : ` || (select jsonb_build_object('fields', ${columnsObject(
          "x",
          extras.map((extra) => extra.name),
        )}) from ${variants} x where x.${v("id")} = v_id)`
  };
end;
$$;
${userGrant(`${fn("upsert_variant")}(${variantArgs}${extraArg.type})`)}

-- Sets a variant's rank key among the product's variants.
create or replace function ${fn("rank_variant")}(variant uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  if rank_variant.rank is null or rank_variant.rank !~ ${rank.pattern} then
    ${fail("CATALOG_RANK_INVALID", "not a rank key", "22023")}
  end if;
  select x.${v("tenant")} into v_tenant from ${variants} x where x.${v("id")} = rank_variant.variant;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  update ${variants} x set ${v("rank")} = ${rank.write("rank_variant.rank")}, ${v("updatedAt")} = now() where x.${v("id")} = rank_variant.variant;
  return true;
end;
$$;
${userGrant(`${fn("rank_variant")}(uuid, text)`)}

-- Removes a variant for good with its prices; false when it was already gone.
-- Needs permissions.purge, which falls back to catalog.manage.
create or replace function ${fn("purge_variant")}(variant uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_product uuid;
begin
  select x.${v("tenant")}, x.${v("product")} into v_tenant, v_product from ${variants} x where x.${v("id")} = purge_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant", names.purge)}${historyCheck("purge_variant.variant", "CATALOG_VARIANT_IN_USE")}
  delete from ${variants} x where x.${v("id")} = purge_variant.variant;
  ${ctx.record({
    type: "product_variant.purged",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', purge_variant.variant, 'productId', v_product)`,
    subject: `'variants/' || purge_variant.variant::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("purge_variant")}(uuid)`)}
`;
}
