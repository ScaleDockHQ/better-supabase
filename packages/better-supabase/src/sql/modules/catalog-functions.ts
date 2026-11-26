import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { Names } from "./catalog-names.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
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
import { catalogRank } from "./catalog-names.ts";
import { stockHistory } from "./inventory-stock.ts";

export const SLUG = "'^[a-z0-9]+(?:-[a-z0-9]+)*$'";

/** The default product statuses and their transitions, without a state machine. */
const STATUS_EDGES: Readonly<Record<string, readonly string[]>> = {
  draft: ["active", "archived"],
  active: ["draft", "archived"],
  archived: ["draft"],
};

/** The columns your schema files add, which the products table gets. */
export const productExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.extraColumns("products", ["id", "slug", "status", "fields"]);

/**
 * The columns your schema files add, which `upsert_variant` writes from
 * `fields`.
 */
export const variantExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.extraColumns("variants", ["id", "sku", "rank", "fields"]);

/**
 * The columns your schema files add, which `upsert_category` writes from
 * `fields`.
 */
export const categoryExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.hasTable("categories")
    ? ctx.extraColumns("categories", ["id", "slug", "rank", "fields"])
    : [];

/**
 * The product columns `upsert_product` sets: without a prices table, the
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

/** `upsert_product`'s argument types after `kind`, without the extra fields. */
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

const QUALIFIED = /^[A-Za-z_][\w$]*\.[A-Za-z_][\w$]*$/;

/** `options.variantInUse` as a quoted function name, or undefined. */
function variantInUse(ctx: BlockSqlContext): string | undefined {
  const value = ctx.text("variantInUse", "");

  if (value === "") {
    return undefined;
  }

  if (!QUALIFIED.test(value)) {
    throw new TypeError(
      "blocks.catalog.options.variantInUse must be a schema-qualified function name, such as public.variant_in_use",
    );
  }

  return value.split(".").map(sqlIdent).join(".");
}

export function guard(
  names: Names,
  tenant: string,
  key: string = names.manage,
): string {
  return `if not (auth.role() = 'service_role' or ${names.scope.can(tenant, key)}) then
    ${fail("CATALOG_FORBIDDEN", "not allowed to manage the catalog")}
  end if;`;
}

/** A `bigint` from a `text` amount of minor units, or `null` when it isn't one. */
export function amountOf(value: string): string {
  return `case when ${value} ~ '^[0-9]{1,18}$' then ${value}::bigint end`;
}

/** The guard a purge runs when the stock ledger has movements for the record. */
export function stockHistoryCheck(
  ctx: BlockSqlContext,
): (variantFilter: string, code: string) => string {
  const inventory = ctx.installed("inventory")
    ? ctx.of("inventory")
    : undefined;

  return (variantFilter, code) =>
    inventory === undefined
      ? ""
      : `
  if ${stockHistory(inventory, (variant) => `${variant} in (${variantFilter})`)} then
    ${fail(code, "the stock ledger has movements for this record; archive it instead", "23503")}
  end if;`;
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
  const oldArgs = [baseArgs, ...productSettingTypes(ctx)].join(", ");
  const saveArgs = `${oldArgs}, text[]`;

  const clearable = [
    ...settings.map(([logical]) => logical),
    "slug",
    ...(desc ? ["description"] : []),
  ];

  const clears = (name: string): string =>
    `${sqlString(name)} = any (coalesce(upsert_product.clear, '{}'::text[]))`;

  const inserted = insertExtraColumns(
    products,
    extras,
    "coalesce(upsert_product.fields, '{}'::jsonb)",
  );

  const settingParams = `${settings
    .map(([, param, type]) => `, ${param} ${type} default null`)
    .join("")}, clear text[] default null`;

  const settingSets = settings.map(
    ([logical, param]) =>
      `${p(logical)} = case when ${clears(logical)} then null else coalesce(${logical === "currency" ? `upper(upsert_product.${param})` : `upsert_product.${param}`}, x.${p(logical)}) end`,
  );

  const settingSet = settingSets.map((set) => `, ${set}`).join("");

  const settingWrite =
    settings.length === 0
      ? ""
      : `
  if v_created then
    update ${products} x set ${settingSets.join(",\n      ")}
    where x.${p("id")} = v_id;
  end if;`;

  const clearCheck = `
  if exists (select 1 from unnest(coalesce(upsert_product.clear, '{}'::text[])) c where c <> all (${sqlString(`{${clearable.join(",")}}`)}::text[])) then
    ${fail("CATALOG_CLEAR_INVALID", `clear names only ${clearable.join(", ")}`, "22023")}
  end if;`;

  const staleDrops = `drop function if exists ${fn("upsert_product")}(${baseArgs});
drop function if exists ${fn("upsert_product")}(${baseArgs}, jsonb);
drop function if exists ${fn("upsert_product")}(${oldArgs});
drop function if exists ${fn("upsert_product")}(${oldArgs}, jsonb);
`;

  const draftless = ctx.appValues("products", "status", "draft").length === 0;

  const edges = Object.entries(STATUS_EDGES)
    .map(([from, to]): [string, readonly string[]] => [
      from,
      draftless && from === "archived" ? [...to, "active"] : to,
    ])
    .map(
      ([from, to]) =>
        `    when ${sqlString(from)} then v_to = any (${sqlString(`{${to.join(",")}}`)}::text[])`,
    )
    .join("\n");

  const historyCheck = stockHistoryCheck(ctx);

  return `
-- Creates a product (product null) or updates one. Returns its id, slug and
-- status. On an update a null argument keeps the column and clear names the
-- columns to empty; a cleared slug is derived from the title again.
${staleDrops}${extraFieldsArg(extras).drop(fn("upsert_product"), saveArgs)}
create or replace function ${fn("upsert_product")}(tenant ${ctx.idType}, product uuid, title text, slug text, description text, kind text${settingParams}${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := upsert_product.product;
  v_title text := upsert_product.title;
  v_slug text := nullif(upsert_product.slug, '');
  v_status text;
  v_created boolean := upsert_product.product is null;${desc ? "\n  v_defaults jsonb;" : ""}
begin
  if v_created then
    ${guard(names, "upsert_product.tenant", names.create)}
  else
    ${guard(names, "upsert_product.tenant", names.update)}
  end if;${clearCheck}
  if not v_created then
    select coalesce(v_title, x.${p("title")}), case when v_slug is null and not ${clears("slug")} then x.${p("slug")} else v_slug end
    into v_title, v_slug
    from ${products} x where x.${p("id")} = upsert_product.product and x.${p("tenant")} = upsert_product.tenant;
    if not found then
      ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
    end if;
  end if;
  v_slug := coalesce(v_slug, trim(both '-' from regexp_replace(lower(v_title), '[^a-z0-9]+', '-', 'g')));
  if v_slug is null or v_slug !~ ${SLUG} then
    ${fail("CATALOG_SLUG_INVALID", "the slug must be lower-case letters, digits and hyphens", "22023")}
  end if;
  ${ctx.hook("before_product_save", [
    [ctx.idType, "upsert_product.tenant"],
    ["uuid", "upsert_product.product"],
    ["text", "v_title"],
    ["text", "v_slug"],
    ["text", "upsert_product.kind"],
  ])}
  begin
    if v_created then${desc ? `\n      ${columnDefaults(products, [[p("description"), "upsert_product.description"]], "v_defaults")}` : ""}
      insert into ${products} (${p("tenant")}, ${p("title")}, ${p("slug")}${desc ? `, ${p("description")}` : ""}${kind ? `, ${p("kind")}` : ""}${inserted.columns})
      values (upsert_product.tenant, v_title, v_slug${desc ? `, ${withColumnDefault(products, p("description"), "upsert_product.description", "v_defaults")}` : ""}${kind ? `, ${ctx.cast("products", "kind", "coalesce(upsert_product.kind, 'physical')")}` : ""}${inserted.values})
      returning ${p("id")}, ${ctx.label("products", "status", p("status"))} into v_id, v_status;
    else
      update ${products} x set ${p("title")} = v_title, ${p("slug")} = v_slug${desc ? `, ${p("description")} = case when ${clears("description")} then null else coalesce(upsert_product.description, x.${p("description")}) end` : ""}${kind ? `, ${p("kind")} = coalesce(${ctx.cast("products", "kind", "upsert_product.kind")}, x.${p("kind")})` : ""}, ${p("updatedAt")} = now()${settingSet}${updateExtraColumns(products, extras, "upsert_product.fields")}
      where x.${p("id")} = upsert_product.product and x.${p("tenant")} = upsert_product.tenant
      returning ${ctx.label("products", "status", `x.${p("status")}`)} into v_status;
      if not found then
        ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${uniqueViolationOn(products, p("slug"), fail("CATALOG_SLUG_TAKEN", "another product has this slug", "23505"))}
  end;${settingWrite}
  if v_created then
    ${ctx.record({
      type: "product.created",
      payload: `jsonb_build_object('organizationId', upsert_product.tenant, 'id', v_id, 'slug', v_slug, 'kind', ${kind ? "coalesce(upsert_product.kind, 'physical')" : "null"})`,
      subject: `'products/' || v_id::text`,
      tenant: "upsert_product.tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "product.updated",
      payload: `jsonb_build_object('organizationId', upsert_product.tenant, 'id', v_id, 'slug', v_slug)`,
      subject: `'products/' || v_id::text`,
      tenant: "upsert_product.tenant",
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
${userGrant(`${fn("upsert_product")}(${saveArgs}${extraFieldsArg(extras).type})`)}

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
  v_from_raw text;
  v_to text := ${ctx.label("products", "status", "set_product_status.status")};
  v_to_raw text;
begin
  select x.${p("tenant")}, ${ctx.label("products", "status", `x.${p("status")}`)}, x.${p("status")}::text into v_tenant, v_from, v_from_raw from ${products} x where x.${p("id")} = set_product_status.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if v_to is null or v_to not in ('draft', 'active', 'archived') then
    ${fail("CATALOG_STATUS_INVALID", "the status must be draft, active or archived", "22023")}
  end if;
  v_to_raw := (${ctx.cast("products", "status", "set_product_status.status")})::text;
  if v_from_raw = v_to_raw then
    return jsonb_build_object('id', set_product_status.product, 'status', v_from, 'from', v_from);
  end if;
${
  governed
    ? ""
    : `  if v_from <> v_to and not (case v_from
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
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product, 'from', v_from, 'to', v_to)`,
    subject: `'products/' || set_product_status.product::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  if v_to = 'archived' then
    ${ctx.record({
      type: "product.archived",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product)`,
      subject: `'products/' || set_product_status.product::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  elsif v_from = 'archived' then
    ${ctx.record({
      type: "product.restored",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product)`,
      subject: `'products/' || set_product_status.product::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  return jsonb_build_object('id', set_product_status.product, 'status', v_to, 'from', v_from);
end;
$$;
${userGrant(`${fn("set_product_status")}(uuid, text)`)}

-- Archives a product: it takes status archived, which takes it off the
-- storefront and out of carts, and records product.archived. Its variants,
-- prices and stock stay. Does nothing when it is archived already.
create or replace function ${fn("archive_product")}(product uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return ${fn("set_product_status")}(archive_product.product, 'archived');
end;
$$;
${userGrant(`${fn("archive_product")}(uuid)`)}

-- Brings an archived product back as a draft (as active when the app has no
-- draft status), so it is published again on purpose, and records
-- product.restored. Does nothing when it is not archived.
create or replace function ${fn("restore_product")}(product uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select ${ctx.label("products", "status", `x.${p("status")}`)} into v_status from ${products} x where x.${p("id")} = restore_product.product;
  if v_status is distinct from 'archived' then
    return ${fn("set_product_status")}(restore_product.product, coalesce(v_status, 'archived'));
  end if;
  return ${fn("set_product_status")}(restore_product.product, ${sqlString(draftless ? "active" : "draft")});
end;
$$;
${userGrant(`${fn("restore_product")}(uuid)`)}

-- Removes a product for good with its options, variants and prices; false
-- when it was already gone. Needs permissions.purge, which falls back to
-- catalog.manage.
create or replace function ${fn("purge_product")}(product uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = purge_product.product;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant", names.purge)}${historyCheck(`select v.${ctx.col("variants", "id")} from ${ctx.table("variants")} v where v.${ctx.col("variants", "product")} = purge_product.product`, "CATALOG_PRODUCT_IN_USE")}
  delete from ${products} x where x.${p("id")} = purge_product.product;
  ${ctx.record({
    type: "product.purged",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', purge_product.product)`,
    subject: `'products/' || purge_product.product::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("purge_product")}(uuid)`)}
`;
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
  const linked = ctx.hasTable("variantValues");
  const vv = (column: string): string => ctx.col("variantValues", column);

  const retires =
    typeof ctx.config.columns["variants"]?.["status"] === "string" &&
    ctx.has("variants", "status");

  const inUse = variantInUse(ctx);

  const inventory = ctx.installed("inventory")
    ? ctx.of("inventory")
    : undefined;

  const referenced = [
    ...(inUse === undefined ? [] : [`${inUse}(v_variant)`]),
    ...(inventory === undefined
      ? []
      : [stockHistory(inventory, (variant) => `${variant} = v_variant`)]),
  ];

  const retire = retires
    ? `
      update ${variants} x set ${v("status")} = ${ctx.value("variants", "status", "archived")}, ${v("updatedAt")} = now() where x.${v("id")} = v_variant;
      delete from ${ctx.table("variantValues")} x where x.${vv("variant")} = v_variant;`
    : `
      ${fail("CATALOG_OPTION_VALUE_IN_USE", "a variant this list removes is still in use", "23503")}`;

  const dropVariant = (product: string): string => `
      delete from ${variants} x where x.${v("id")} = v_variant;
      ${ctx
        .record({
          type: "product_variant.purged",
          payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', ${product})`,
          subject: `'variants/' || v_variant::text`,
          tenant: "v_tenant",
          audit: false,
        })
        .replaceAll("\n", "\n    ")}`;

  const settle = (product: string): string => `${
    referenced.length === 0
      ? ""
      : `
    if ${referenced.join(" or ")} then${retire}
      continue;
    end if;`
  }
    begin${dropVariant(product)}
    exception when foreign_key_violation then${retire}
    end;`;

  const removeVariants = linked
    ? `
  for v_variant in
    select distinct x.${vv("variant")} from ${ctx.table("variantValues")} x
    join ${values} y on y.${ov("id")} = x.${vv("value")}
    where y.${ov("option")} = v_id and not (y.${ov("value")} = any (upsert_product_option.option_values))
  loop${settle("upsert_product_option.product")}
  end loop;`
    : "";

  const linkVariants = linked
    ? `
  if v_new then
    insert into ${ctx.table("variantValues")} (${vv("tenant")}, ${vv("variant")}, ${vv("value")})
    select v_tenant, x.${v("id")}, (select y.${ov("id")} from ${values} y where y.${ov("option")} = v_id and y.${ov("value")} = upsert_product_option.option_values[1])
    from ${variants} x where x.${v("product")} = upsert_product_option.product;
  end if;`
    : "";

  return `
-- Creates an option (option null) or updates one, with its values in order.
-- Values missing from the list are removed with the variants that use them;
-- a variant something still references is archived instead.
create or replace function ${fn("upsert_product_option")}(product uuid, option uuid, name text, option_values text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_id uuid := upsert_product_option.option;
  v_last text;
  v_rank text;
  v_value text;
  v_variant uuid;
  v_new boolean := upsert_product_option.option is null;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = upsert_product_option.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if coalesce(cardinality(upsert_product_option.option_values), 0) = 0 then
    ${fail("CATALOG_OPTION_EMPTY", "an option needs at least one value", "22023")}
  end if;
  if (select count(distinct x) from unnest(upsert_product_option.option_values) x) <> cardinality(upsert_product_option.option_values) then
    ${fail("CATALOG_OPTION_DUPLICATE", "an option lists the same value twice", "22023")}
  end if;
  begin
    if v_id is null then${
      linked
        ? ""
        : `
      if exists (select 1 from ${variants} x where x.${v("product")} = upsert_product_option.product) then
        ${fail("CATALOG_OPTION_HAS_VARIANTS", "add options before the product has variants", "22023")}
      end if;`
    }
      select max(${rank.order(`x.${o("rank")}`)}) into v_last from ${options} x where x.${o("product")} = upsert_product_option.product;
      insert into ${options} (${o("tenant")}, ${o("product")}, ${o("name")}, ${o("rank")})
      values (v_tenant, upsert_product_option.product, upsert_product_option.name, ${rank.write(rank.after("v_last"))})
      returning ${o("id")} into v_id;
    else
      update ${options} x set ${o("name")} = upsert_product_option.name
      where x.${o("id")} = upsert_product_option.option and x.${o("product")} = upsert_product_option.product;
      if not found then
        ${fail("CATALOG_OPTION_NOT_FOUND", "option not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_OPTION_TAKEN", "the product has another option with this name", "23505")}
  end;${removeVariants}
  begin
    delete from ${values} x where x.${ov("option")} = v_id and not (x.${ov("value")} = any (upsert_product_option.option_values));
  exception when foreign_key_violation then
    ${fail("CATALOG_OPTION_VALUE_IN_USE", "a variant uses a value this list removes", "23503")}
  end;
  v_rank := null;
  foreach v_value in array upsert_product_option.option_values loop
    v_rank := ${rank.after("v_rank")};
    update ${values} x set ${ov("rank")} = ${rank.write("v_rank")} where x.${ov("option")} = v_id and x.${ov("value")} = v_value;
    if not found then
      insert into ${values} (${ov("tenant")}, ${ov("option")}, ${ov("value")}, ${ov("rank")})
      values (v_tenant, v_id, v_value, ${rank.write("v_rank")});
    end if;
  end loop;${linkVariants}
  return jsonb_build_object(
    'id', v_id,
    'values', (select coalesce(jsonb_agg(jsonb_build_object('id', x.${ov("id")}, 'value', x.${ov("value")}) order by ${rank.order(`x.${ov("rank")}`)}), '[]'::jsonb) from ${values} x where x.${ov("option")} = v_id)
  );
end;
$$;
${userGrant(`${fn("upsert_product_option")}(uuid, uuid, text, text[])`)}

-- Puts a product's options in the given order; the list names each once.
create or replace function ${fn("reorder_product_options")}(product uuid, options uuid[])
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_rank text;
  v_option uuid;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = reorder_product_options.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if coalesce(cardinality(reorder_product_options.options), 0) <> (select count(*) from ${options} x where x.${o("product")} = reorder_product_options.product)
    or (select count(distinct y) from unnest(reorder_product_options.options) y) <> cardinality(reorder_product_options.options)
    or exists (select 1 from unnest(reorder_product_options.options) y where not exists (select 1 from ${options} x where x.${o("id")} = y and x.${o("product")} = reorder_product_options.product)) then
    ${fail("CATALOG_OPTION_ORDER_INVALID", "the list must name each option of the product once", "22023")}
  end if;
  foreach v_option in array reorder_product_options.options loop
    v_rank := ${rank.after("v_rank")};
    update ${options} x set ${o("rank")} = ${rank.write("v_rank")} where x.${o("id")} = v_option;
  end loop;
  return true;
end;
$$;
${userGrant(`${fn("reorder_product_options")}(uuid, uuid[])`)}

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
  ${guard(names, "v_tenant", names.update)}
  begin
    delete from ${options} x where x.${o("id")} = delete_product_option.option;
  exception when foreign_key_violation then
    ${fail("CATALOG_OPTION_VALUE_IN_USE", "a variant uses a value of this option", "23503")}
  end;
  return true;
end;
$$;
${userGrant(`${fn("delete_product_option")}(uuid)`)}
${linked ? optionMatrix(ctx, names, settle("set_product_options.product")) : ""}`;
}

function optionMatrix(
  ctx: BlockSqlContext,
  names: Names,
  settle: string,
): string {
  const { fn } = names;
  const rank = catalogRank(ctx);
  const products = ctx.table("products");
  const options = ctx.table("options");
  const values = ctx.table("optionValues");
  const variants = ctx.table("variants");
  const links = ctx.table("variantValues");
  const p = (column: string): string => ctx.col("products", column);
  const o = (column: string): string => ctx.col("options", column);
  const ov = (column: string): string => ctx.col("optionValues", column);
  const v = (column: string): string => ctx.col("variants", column);
  const vv = (column: string): string => ctx.col("variantValues", column);
  const limit = ctx.number("maxVariants", 100);

  if (!Number.isInteger(limit) || limit < 1) {
    throw new TypeError(
      "blocks.catalog.options.maxVariants must be a whole number of 1 or more",
    );
  }

  const live = (alias: string): string =>
    typeof ctx.config.columns["variants"]?.["status"] === "string" &&
    ctx.has("variants", "status")
      ? ` and ${ctx.is("variants", "status", `${alias}.${v("status")}::text`, ["archived"], true)}`
      : "";

  const valueSet = (alias: string): string =>
    `coalesce((select array_agg(y.${vv("value")} order by y.${vv("value")}) from ${links} y where y.${vv("variant")} = ${alias}.${v("id")}), '{}'::uuid[])`;

  const titles = ctx.has("variants", "title")
    ? `
  if set_product_options.title_separator is not null then
    update ${variants} x set ${v("title")} = t.title, ${v("updatedAt")} = now()
    from (
      select y.${vv("variant")} as variant, string_agg(z.${ov("value")}, set_product_options.title_separator order by ${rank.order(`k.${o("rank")}`)}) as title
      from ${links} y
      join ${values} z on z.${ov("id")} = y.${vv("value")}
      join ${options} k on k.${o("id")} = z.${ov("option")}
      where k.${o("product")} = set_product_options.product
      group by y.${vv("variant")}
    ) t
    where x.${v("id")} = t.variant and x.${v("title")} is distinct from t.title${live("x")};
  end if;`
    : "";

  return `
-- Replaces a product's options by name and makes its variants the full matrix
-- of their values in one transaction.
create or replace function ${fn("set_product_options")}(product uuid, options jsonb, title_separator text default ' / ')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_slug text;
  v_item jsonb;
  v_option uuid;
  v_ids uuid[] := '{}';
  v_variant uuid;
  v_combo uuid[];
  v_label text;
  v_count numeric := 1;
  v_sku_required boolean;
begin
  select x.${p("tenant")}, x.${p("slug")} into v_tenant, v_slug from ${products} x where x.${p("id")} = set_product_options.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if jsonb_typeof(set_product_options.options) is distinct from 'array'
    or exists (
      select 1 from jsonb_array_elements(set_product_options.options) e
      where jsonb_typeof(e) is distinct from 'object'
        or jsonb_typeof(e -> 'name') is distinct from 'string'
        or jsonb_typeof(e -> 'values') is distinct from 'array'
        or exists (select 1 from jsonb_array_elements(e -> 'values') y where jsonb_typeof(y) <> 'string')
    ) then
    ${fail("CATALOG_OPTIONS_INVALID", "options is a list of { name, values } with text values", "22023")}
  end if;
  if (select count(distinct e ->> 'name') from jsonb_array_elements(set_product_options.options) e) <> jsonb_array_length(set_product_options.options) then
    ${fail("CATALOG_OPTION_TAKEN", "the list names an option twice", "23505")}
  end if;
  for v_item in select e from jsonb_array_elements(set_product_options.options) e loop
    v_count := v_count * jsonb_array_length(v_item -> 'values');
  end loop;
  if v_count > ${limit} then
    ${fail("CATALOG_VARIANT_LIMIT", `a product has at most ${limit} variants`, "22023")}
  end if;
  for v_option in
    select x.${o("id")} from ${options} x
    where x.${o("product")} = set_product_options.product
      and not (x.${o("name")} = any (array(select e ->> 'name' from jsonb_array_elements(set_product_options.options) e)))
  loop
    delete from ${links} y using ${values} z where y.${vv("value")} = z.${ov("id")} and z.${ov("option")} = v_option;
    delete from ${options} x where x.${o("id")} = v_option;
  end loop;
  for v_variant in
    select d.id from (
      select x.${v("id")} as id, row_number() over (partition by ${valueSet("x")} order by ${rank.order(`x.${v("rank")}`)}, x.${v("id")}) as n
      from ${variants} x where x.${v("product")} = set_product_options.product${live("x")}
    ) d where d.n > 1
  loop${settle}
  end loop;
  for v_item in select e from jsonb_array_elements(set_product_options.options) with ordinality as a(e, n) order by a.n loop
    select x.${o("id")} into v_option from ${options} x where x.${o("product")} = set_product_options.product and x.${o("name")} = v_item ->> 'name';
    v_option := (${fn("upsert_product_option")}(set_product_options.product, v_option, v_item ->> 'name', array(select y from jsonb_array_elements_text(v_item -> 'values') with ordinality as b(y, n) order by b.n)) ->> 'id')::uuid;
    v_ids := v_ids || v_option;
  end loop;
  if cardinality(v_ids) > 0 then
    perform ${fn("reorder_product_options")}(set_product_options.product, v_ids);
  end if;
  select a.attnotnull into v_sku_required from pg_catalog.pg_attribute a
  where a.attrelid = ${sqlString(variants)}::regclass and a.attname = ${sqlString(v("sku").replaceAll('"', ""))};
  for v_combo, v_label in
    with recursive k as (
      select x.${o("id")} as id, row_number() over (order by ${rank.order(`x.${o("rank")}`)}) as n
      from ${options} x where x.${o("product")} = set_product_options.product
    ), z as (
      select y.${ov("id")} as id, y.${ov("value")} as value, y.${ov("option")} as option, row_number() over (partition by y.${ov("option")} order by ${rank.order(`y.${ov("rank")}`)}) as n
      from ${values} y where y.${ov("option")} in (select k.id from k)
    ), c(depth, ids, labels, sort) as (
      select 0::bigint, '{}'::uuid[], '{}'::text[], '{}'::bigint[]
      union all
      select k.n, c.ids || z.id, c.labels || z.value, c.sort || z.n
      from c join k on k.n = c.depth + 1 join z on z.option = k.id
    )
    select c.ids, array_to_string(c.labels, '-') from c where c.depth = (select count(*) from k) order by c.sort
  loop
    if not exists (
      select 1 from ${variants} x
      where x.${v("product")} = set_product_options.product${live("x")}
        and ${valueSet("x")} = (select coalesce(array_agg(u order by u), '{}'::uuid[]) from unnest(v_combo) u)
    ) then
      perform ${fn("upsert_variant")}(set_product_options.product, null, case when v_sku_required then upper(trim(both '-' from regexp_replace(concat_ws('-', v_slug, nullif(v_label, '')), '[^A-Za-z0-9]+', '-', 'g'))) end, v_combo, null, null, null, null, null);
    end if;
  end loop;${titles}
  return jsonb_build_object(
    'options', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.${o("id")},
        'name', k.${o("name")},
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', z.${ov("id")}, 'value', z.${ov("value")}) order by ${rank.order(`z.${ov("rank")}`)}), '[]'::jsonb) from ${values} z where z.${ov("option")} = k.${o("id")})
      ) order by ${rank.order(`k.${o("rank")}`)}), '[]'::jsonb)
      from ${options} k where k.${o("product")} = set_product_options.product
    ),
    'variants', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x.${v("id")}, 'sku', x.${v("sku")}, 'optionValueIds', to_jsonb(${valueSet("x")})) order by ${rank.order(`x.${v("rank")}`)}), '[]'::jsonb)
      from ${variants} x where x.${v("product")} = set_product_options.product${live("x")}
    )
  );
end;
$$;
${userGrant(`${fn("set_product_options")}(uuid, jsonb, text)`)}
`;
}
