import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { RankSql } from "../rank-sql.ts";
import type { BlockSqlScope } from "../scope.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { rankSql } from "../rank-sql.ts";
import {
  columnsObject,
  extraFieldsArg,
  fail,
  insertExtraColumns,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { stockHistory } from "./inventory-stock.ts";

export const SLUG = "'^[a-z0-9]+(?:-[a-z0-9]+)*$'";

/** The default product statuses and their transitions, without a state machine. */
const STATUS_EDGES: Readonly<Record<string, readonly string[]>> = {
  draft: ["active", "archived"],
  active: ["draft", "archived"],
  archived: ["draft"],
};

/** `options.extraColumns`, which the products table gets. */
export const productExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.extraColumns("products", ["id", "slug", "status", "fields"]);

/** `options.variantExtraColumns`, which `save_variant` writes from `fields`. */
export const variantExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.extraColumns(
    "variants",
    ["id", "sku", "rank", "fields"],
    "variantExtraColumns",
  );

/** `options.categoryExtraColumns`, which `save_category` writes from `fields`. */
export const categoryExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.hasTable("categories")
    ? ctx.extraColumns(
        "categories",
        ["id", "slug", "rank", "fields"],
        "categoryExtraColumns",
      )
    : [];

/**
 * The product columns `save_product` sets: without a prices table, the
 * product's price in minor units and its currency, and whether inventory counts
 * stock when variants don't say. Each is a parameter with a null default that
 * leaves the column as it is.
 */
function productSettings(
  ctx: BlockSqlContext,
): readonly (readonly [string, string, string])[] {
  const onVariant = !ctx.hasTable("prices");

  const settings = [
    ["price", "price", "bigint", onVariant],
    ["currency", "currency", "text", onVariant],
    [
      "trackInventory",
      "track_inventory",
      "boolean",
      !ctx.has("variants", "trackInventory"),
    ],
  ] as const;

  return settings
    .filter(([logical, , , used]) => used && ctx.has("products", logical))
    .map(([logical, param, type]) => [logical, param, type] as const);
}

/** `save_product`'s argument types after `kind`, without the extra fields. */
export const productSettingTypes = (ctx: BlockSqlContext): readonly string[] =>
  productSettings(ctx).map(([, , type]) => type);

export function storefrontOption(ctx: BlockSqlContext): boolean {
  const value = ctx.text("storefront", "private");

  if (value !== "public" && value !== "private") {
    throw new TypeError(
      'blocks.catalog.options.storefront must be "public" or "private"',
    );
  }

  if (value === "public" && !ctx.hasTable("storefronts")) {
    throw new TypeError(
      'blocks.catalog.options.storefront "public" needs the storefronts table',
    );
  }

  return value === "public";
}

/**
 * Whether a `state-machine` machine drives the products table's status column:
 * `set_product_status` then writes the status and leaves the transition rules,
 * history and `status.changed` to the machine's trigger.
 */
function machineGoverns(ctx: BlockSqlContext): boolean {
  if (!ctx.installed("state-machine")) {
    return false;
  }

  const raw = ctx.of("state-machine").option("machines");

  if (typeof raw !== "object" || raw === null) {
    return false;
  }

  const { schema, name } = ctx.tableName("products");
  const column = ctx.col("products", "status").replaceAll('"', "");

  return Object.values(raw).some((entry: unknown) => {
    if (!isRecord(entry)) {
      return false;
    }

    const table = entry["table"];
    const col = entry["column"];

    return (
      (table === `${schema}.${name}` ||
        (schema === "public" && table === name)) &&
      col === column
    );
  });
}

export interface Names {
  /** The block's scope checks. */
  readonly scope: BlockSqlScope;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly read: string;
}

/** `blocks.catalog.options.rankType`: rank keys or integer positions. */
export function catalogRank(ctx: BlockSqlContext): RankSql {
  const type = ctx.text("rankType", "text");

  if (type !== "text" && type !== "integer") {
    throw new TypeError(
      'blocks.catalog.options.rankType must be "text" or "integer"',
    );
  }

  return rankSql(type);
}

export function guard(names: Names, tenant: string): string {
  return `if not (auth.role() = 'service_role' or ${names.scope.can(tenant, names.manage)}) then
    ${fail("CATALOG_FORBIDDEN", "not allowed to manage the catalog")}
  end if;`;
}

/** A `bigint` from a `text` amount of minor units, or `null` when it isn't one. */
export function amountOf(value: string): string {
  return `case when ${value} ~ '^[0-9]{1,18}$' then ${value}::bigint end`;
}

export function productFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const products = ctx.table("products");
  const p = (column: string): string => ctx.col("products", column);
  const desc = ctx.has("products", "description");
  const kind = ctx.has("products", "kind");
  const governed = machineGoverns(ctx);
  const extras = productExtras(ctx);
  const settings = productSettings(ctx);
  const baseArgs = `${ctx.idType}, uuid, text, text, text, text`;
  const saveArgs = [baseArgs, ...productSettingTypes(ctx)].join(", ");

  const settingParams = settings
    .map(([, param, type]) => `, ${param} ${type} default null`)
    .join("");

  const settingWrite =
    settings.length === 0
      ? ""
      : `
  update ${products} x set ${settings
    .map(
      ([logical, param]) =>
        `${p(logical)} = coalesce(${logical === "currency" ? `upper(save_product.${param})` : `save_product.${param}`}, x.${p(logical)})`,
    )
    .join(", ")}
  where x.${p("id")} = v_id;`;

  const staleDrops =
    settings.length === 0
      ? ""
      : `drop function if exists ${fn("save_product")}(${baseArgs});
drop function if exists ${fn("save_product")}(${baseArgs}, jsonb);
`;

  const edges = Object.entries(STATUS_EDGES)
    .map(
      ([from, to]) =>
        `    when ${sqlString(from)} then set_product_status.status = any (${sqlString(`{${to.join(",")}}`)}::text[])`,
    )
    .join("\n");

  const inventory = ctx.installed("inventory")
    ? ctx.of("inventory")
    : undefined;

  const historyCheck = (variantFilter: string, code: string): string =>
    inventory === undefined
      ? ""
      : `
  if ${stockHistory(inventory, (variant) => `${variant} in (${variantFilter})`)} then
    ${fail(code, "the stock ledger has movements for this record; archive it instead", "23503")}
  end if;`;

  return `
-- Creates a product (product null) or updates one. Returns its id, slug and
-- status.${settings.length === 0 ? "" : " A null price, currency or track_inventory keeps the column."}
${staleDrops}${extraFieldsArg(extras).drop(fn("save_product"), saveArgs)}
create or replace function ${fn("save_product")}(tenant ${ctx.idType}, product uuid, title text, slug text, description text, kind text${settingParams}${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_product.product;
  v_slug text := coalesce(nullif(save_product.slug, ''), trim(both '-' from regexp_replace(lower(save_product.title), '[^a-z0-9]+', '-', 'g')));
  v_status text;
  v_created boolean := save_product.product is null;
begin
  ${guard(names, "save_product.tenant")}
  if v_slug is null or v_slug !~ ${SLUG} then
    ${fail("CATALOG_SLUG_INVALID", "the slug must be lower-case letters, digits and hyphens", "22023")}
  end if;
  ${ctx.hook("before_product_save", [
    [ctx.idType, "save_product.tenant"],
    ["uuid", "save_product.product"],
    ["text", "save_product.title"],
    ["text", "v_slug"],
    ["text", "save_product.kind"],
  ])}
  begin
    if v_created then
      insert into ${products} (${p("tenant")}, ${p("title")}, ${p("slug")}${desc ? `, ${p("description")}` : ""}${kind ? `, ${p("kind")}` : ""})
      values (save_product.tenant, save_product.title, v_slug${desc ? ", save_product.description" : ""}${kind ? `, ${ctx.cast("products", "kind", "coalesce(save_product.kind, 'physical')")}` : ""})
      returning ${p("id")}, ${ctx.label("products", "status", p("status"))} into v_id, v_status;
    else
      update ${products} x set ${p("title")} = save_product.title, ${p("slug")} = v_slug${desc ? `, ${p("description")} = save_product.description` : ""}${kind ? `, ${p("kind")} = coalesce(${ctx.cast("products", "kind", "save_product.kind")}, x.${p("kind")})` : ""}, ${p("updatedAt")} = now()
      where x.${p("id")} = save_product.product and x.${p("tenant")} = save_product.tenant
      returning ${ctx.label("products", "status", `x.${p("status")}`)} into v_status;
      if not found then
        ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_SLUG_TAKEN", "another product has this slug", "23505")}
  end;${settingWrite}${writeExtraColumns(products, extras, "save_product.fields", `x.${p("id")} = v_id`)}
  if v_created then
    ${ctx.record({
      type: "product.created",
      payload: `jsonb_build_object('organizationId', save_product.tenant, 'id', v_id, 'slug', v_slug, 'kind', ${kind ? "coalesce(save_product.kind, 'physical')" : "null"})`,
      subject: `'products/' || v_id::text`,
      tenant: "save_product.tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "product.updated",
      payload: `jsonb_build_object('organizationId', save_product.tenant, 'id', v_id, 'slug', v_slug)`,
      subject: `'products/' || v_id::text`,
      tenant: "save_product.tenant",
      audit: false,
    })}
  end if;
  ${ctx.hook("after_product_save", [
    ["uuid", "v_id"],
    ["boolean", "v_created"],
  ])}
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'status', v_status)${
    extras.length === 0
      ? ""
      : ` || (select jsonb_build_object('fields', ${columnsObject(
          "x",
          extras.map((extra) => extra.name),
        )}) from ${products} x where x.${p("id")} = v_id)`
  };
end;
$$;
${userGrant(`${fn("save_product")}(${saveArgs}${extraFieldsArg(extras).type})`)}

-- Moves a product to another status: draft, active or archived.${governed ? "\n-- A state-machine machine owns the transitions of this table." : ""}
create or replace function ${fn("set_product_status")}(product uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_from text;
begin
  select x.${p("tenant")}, ${ctx.label("products", "status", `x.${p("status")}`)} into v_tenant, v_from from ${products} x where x.${p("id")} = set_product_status.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if set_product_status.status not in ('draft', 'active', 'archived') then
    ${fail("CATALOG_STATUS_INVALID", "the status must be draft, active or archived", "22023")}
  end if;
  if v_from = set_product_status.status then
    return jsonb_build_object('id', set_product_status.product, 'status', v_from, 'from', v_from);
  end if;
${
  governed
    ? ""
    : `  if not (case v_from
${edges}
    else false
  end) then
    ${fail("CATALOG_TRANSITION_INVALID", "the product can't move to this status", "22023")}
  end if;
`
}  update ${products} x set ${p("status")} = ${ctx.cast("products", "status", "set_product_status.status")}, ${p("updatedAt")} = now()
  where x.${p("id")} = set_product_status.product;
  ${ctx.record({
    type: "product.status_changed",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product, 'from', v_from, 'to', set_product_status.status)`,
    subject: `'products/' || set_product_status.product::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return jsonb_build_object('id', set_product_status.product, 'status', set_product_status.status, 'from', v_from);
end;
$$;
${userGrant(`${fn("set_product_status")}(uuid, text)`)}

-- Deletes a product with its options, variants and prices.
create or replace function ${fn("delete_product")}(product uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = delete_product.product;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}${historyCheck(`select v.${ctx.col("variants", "id")} from ${ctx.table("variants")} v where v.${ctx.col("variants", "product")} = delete_product.product`, "CATALOG_PRODUCT_IN_USE")}
  delete from ${products} x where x.${p("id")} = delete_product.product;
  ${ctx.record({
    type: "product.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_product.product)`,
    subject: `'products/' || delete_product.product::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_product")}(uuid)`)}
${variantFunctions(ctx, names, historyCheck)}`;
}

export function optionFunctions(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.hasTable("options") || !ctx.hasTable("optionValues")) {
    return "";
  }

  const { fn } = names;
  const rank = catalogRank(ctx);
  const products = ctx.table("products");
  const options = ctx.table("options");
  const values = ctx.table("optionValues");
  const variants = ctx.table("variants");
  const p = (column: string): string => ctx.col("products", column);
  const o = (column: string): string => ctx.col("options", column);
  const ov = (column: string): string => ctx.col("optionValues", column);
  const v = (column: string): string => ctx.col("variants", column);

  return `
-- Creates an option (option null) or updates one, with its values in order.
-- Values missing from the list are removed; values a variant uses can't be.
create or replace function ${fn("save_product_option")}(product uuid, option uuid, name text, option_values text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_id uuid := save_product_option.option;
  v_last text;
  v_rank text;
  v_value text;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = save_product_option.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if coalesce(cardinality(save_product_option.option_values), 0) = 0 then
    ${fail("CATALOG_OPTION_EMPTY", "an option needs at least one value", "22023")}
  end if;
  if (select count(distinct x) from unnest(save_product_option.option_values) x) <> cardinality(save_product_option.option_values) then
    ${fail("CATALOG_OPTION_DUPLICATE", "an option lists the same value twice", "22023")}
  end if;
  begin
    if v_id is null then
      if exists (select 1 from ${variants} x where x.${v("product")} = save_product_option.product) then
        ${fail("CATALOG_OPTION_HAS_VARIANTS", "add options before the product has variants", "22023")}
      end if;
      select max(${rank.order(`x.${o("rank")}`)}) into v_last from ${options} x where x.${o("product")} = save_product_option.product;
      insert into ${options} (${o("tenant")}, ${o("product")}, ${o("name")}, ${o("rank")})
      values (v_tenant, save_product_option.product, save_product_option.name, ${rank.write(rank.after("v_last"))})
      returning ${o("id")} into v_id;
    else
      update ${options} x set ${o("name")} = save_product_option.name
      where x.${o("id")} = save_product_option.option and x.${o("product")} = save_product_option.product;
      if not found then
        ${fail("CATALOG_OPTION_NOT_FOUND", "option not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_OPTION_TAKEN", "the product has another option with this name", "23505")}
  end;
  begin
    delete from ${values} x where x.${ov("option")} = v_id and not (x.${ov("value")} = any (save_product_option.option_values));
  exception when foreign_key_violation then
    ${fail("CATALOG_OPTION_VALUE_IN_USE", "a variant uses a value this list removes", "23503")}
  end;
  v_rank := null;
  foreach v_value in array save_product_option.option_values loop
    v_rank := ${rank.after("v_rank")};
    update ${values} x set ${ov("rank")} = ${rank.write("v_rank")} where x.${ov("option")} = v_id and x.${ov("value")} = v_value;
    if not found then
      insert into ${values} (${ov("tenant")}, ${ov("option")}, ${ov("value")}, ${ov("rank")})
      values (v_tenant, v_id, v_value, ${rank.write("v_rank")});
    end if;
  end loop;
  return jsonb_build_object(
    'id', v_id,
    'values', (select coalesce(jsonb_agg(jsonb_build_object('id', x.${ov("id")}, 'value', x.${ov("value")}) order by ${rank.order(`x.${ov("rank")}`)}), '[]'::jsonb) from ${values} x where x.${ov("option")} = v_id)
  );
end;
$$;
${userGrant(`${fn("save_product_option")}(uuid, uuid, text, text[])`)}

-- Deletes an option and its values; refused while a variant uses one.
create or replace function ${fn("delete_product_option")}(option uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${o("tenant")} into v_tenant from ${options} x where x.${o("id")} = delete_product_option.option;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  begin
    delete from ${options} x where x.${o("id")} = delete_product_option.option;
  exception when foreign_key_violation then
    ${fail("CATALOG_OPTION_VALUE_IN_USE", "a variant uses a value of this option", "23503")}
  end;
  return true;
end;
$$;
${userGrant(`${fn("delete_product_option")}(uuid)`)}
`;
}

function variantFunctions(
  ctx: BlockSqlContext,
  names: Names,
  historyCheck: (variants: string, code: string) => string,
): string {
  const { fn } = names;
  const rank = catalogRank(ctx);
  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const optional = (column: string): boolean => ctx.has("variants", column);
  const extras = variantExtras(ctx);
  const extraArg = extraFieldsArg(extras);

  const variantArgs =
    "uuid, uuid, text, uuid[], text, text, integer, boolean, boolean";

  const inserted = insertExtraColumns(
    variants,
    extras,
    "coalesce(save_variant.fields, '{}'::jsonb)",
  );

  const tracking = optional("trackInventory")
    ? ""
    : `
  if save_variant.track_inventory is not null then
    ${fail("CATALOG_TRACK_INVENTORY_UNSUPPORTED", "this catalog tracks inventory per product, not per variant", "22023")}
  end if;`;

  const hasValues =
    ctx.hasTable("variantValues") &&
    ctx.hasTable("optionValues") &&
    ctx.hasTable("options");

  const columns: readonly (readonly [string, string])[] = [
    ["sku", "save_variant.sku"],
    ...(optional("title") ? ([["title", "save_variant.title"]] as const) : []),
    ...(optional("barcode")
      ? ([["barcode", "save_variant.barcode"]] as const)
      : []),
    ...(optional("weight")
      ? ([["weight", "save_variant.weight_grams"]] as const)
      : []),
    ...(optional("trackInventory")
      ? ([
          ["trackInventory", "coalesce(save_variant.track_inventory, true)"],
        ] as const)
      : []),
    ["allowBackorder", "coalesce(save_variant.allow_backorder, false)"],
  ];

  const valueChecks = hasValues
    ? (() => {
        const options = ctx.table("options");
        const optionValues = ctx.table("optionValues");
        const variantValues = ctx.table("variantValues");
        const o = (column: string): string => ctx.col("options", column);
        const ov = (column: string): string => ctx.col("optionValues", column);
        const vv = (column: string): string => ctx.col("variantValues", column);

        return {
          check: `  v_wanted := coalesce((select array_agg(distinct x order by x) from unnest(save_variant.option_values) x), '{}'::uuid[]);
  if cardinality(v_wanted) <> coalesce(cardinality(save_variant.option_values), 0)
    or exists (
      select 1 from unnest(v_wanted) x
      where not exists (
        select 1 from ${optionValues} ov join ${options} o on o.${o("id")} = ov.${ov("option")}
        where ov.${ov("id")} = x and o.${o("product")} = save_variant.product
      )
    )
    or (select count(distinct ov.${ov("option")}) from ${optionValues} ov where ov.${ov("id")} = any (v_wanted)) <> cardinality(v_wanted)
    or (select count(*) from ${options} o where o.${o("product")} = save_variant.product) <> cardinality(v_wanted) then
    ${fail("CATALOG_VARIANT_OPTIONS", "a variant needs exactly one value of each product option", "22023")}
  end if;
  if exists (
    select 1 from ${variants} x
    where x.${v("product")} = save_variant.product
      and x.${v("id")} is distinct from save_variant.variant
      and coalesce((select array_agg(y.${vv("value")} order by y.${vv("value")}) from ${variantValues} y where y.${vv("variant")} = x.${v("id")}), '{}'::uuid[]) = v_wanted
  ) then
    ${fail("CATALOG_VARIANT_DUPLICATE", "another variant has these option values", "23505")}
  end if;`,
          write: `  delete from ${variantValues} x where x.${vv("variant")} = v_id and not (x.${vv("value")} = any (v_wanted));
  insert into ${variantValues} (${vv("tenant")}, ${vv("variant")}, ${vv("value")})
  select v_tenant, v_id, x from unnest(v_wanted) x
  on conflict do nothing;`,
        };
      })()
    : {
        check: `  v_wanted := '{}'::uuid[];
  if coalesce(cardinality(save_variant.option_values), 0) > 0 then
    ${fail("CATALOG_VARIANT_OPTIONS", "this catalog has no option values", "22023")}
  end if;
  if exists (select 1 from ${variants} x where x.${v("product")} = save_variant.product and x.${v("id")} is distinct from save_variant.variant) then
    ${fail("CATALOG_VARIANT_DUPLICATE", "a product without options has one variant", "23505")}
  end if;`,
        write: "",
      };

  return `
-- Creates a variant (variant null) or updates one. option_values holds one
-- option value id per product option; no two variants share a combination.
-- fields: the extra columns (options.variantExtraColumns) to set.
${extraArg.drop(fn("save_variant"), variantArgs)}
create or replace function ${fn("save_variant")}(product uuid, variant uuid, sku text, option_values uuid[], title text, barcode text, weight_grams integer, track_inventory boolean, allow_backorder boolean${extraArg.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_id uuid := save_variant.variant;
  v_created boolean := save_variant.variant is null;
  v_wanted uuid[];
  v_last text;
  v_rank text;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = save_variant.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}${tracking}
${valueChecks.check}
  ${ctx.hook("before_variant_save", [
    ["uuid", "save_variant.product"],
    ["uuid", "save_variant.variant"],
    ["text", "save_variant.sku"],
    ["uuid[]", "v_wanted"],
  ])}
  begin
    if v_created then
      select max(${rank.order(`x.${v("rank")}`)}) into v_last from ${variants} x where x.${v("product")} = save_variant.product;
      v_rank := ${rank.after("v_last")};
      insert into ${variants} (${v("tenant")}, ${v("product")}, ${columns.map(([column]) => v(column)).join(", ")}, ${v("rank")}${inserted.columns})
      values (v_tenant, save_variant.product, ${columns.map(([, value]) => value).join(", ")}, ${rank.write("v_rank")}${inserted.values})
      returning ${v("id")} into v_id;
    else
      update ${variants} x set ${columns.map(([column, value]) => `${v(column)} = ${value}`).join(", ")}, ${v("updatedAt")} = now()
      where x.${v("id")} = save_variant.variant and x.${v("product")} = save_variant.product
      returning x.${v("rank")} into v_rank;
      if not found then
        ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
      end if;${writeExtraColumns(variants, extras, "save_variant.fields", `x.${v("id")} = v_id`).replaceAll("\n  ", "\n      ")}
    end if;
  exception when unique_violation then
    ${fail("CATALOG_SKU_TAKEN", "another variant has this SKU", "23505")}
  end;
${valueChecks.write}
  if v_created then
    ${ctx.record({
      type: "variant.created",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', save_variant.sku)`,
      subject: `'variants/' || v_id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "variant.updated",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', save_variant.sku)`,
      subject: `'variants/' || v_id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  ${ctx.hook("after_variant_save", [
    ["uuid", "v_id"],
    ["boolean", "v_created"],
  ])}
  return jsonb_build_object('id', v_id, 'sku', save_variant.sku, 'rank', v_rank)${
    extras.length === 0
      ? ""
      : ` || (select jsonb_build_object('fields', ${columnsObject(
          "x",
          extras.map((extra) => extra.name),
        )}) from ${variants} x where x.${v("id")} = v_id)`
  };
end;
$$;
${userGrant(`${fn("save_variant")}(${variantArgs}${extraArg.type})`)}

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

-- Deletes a variant with its prices.
create or replace function ${fn("delete_variant")}(variant uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_product uuid;
begin
  select x.${v("tenant")}, x.${v("product")} into v_tenant, v_product from ${variants} x where x.${v("id")} = delete_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}${historyCheck("delete_variant.variant", "CATALOG_VARIANT_IN_USE")}
  delete from ${variants} x where x.${v("id")} = delete_variant.variant;
  ${ctx.record({
    type: "variant.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_variant.variant, 'productId', v_product)`,
    subject: `'variants/' || delete_variant.variant::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_variant")}(uuid)`)}
`;
}
