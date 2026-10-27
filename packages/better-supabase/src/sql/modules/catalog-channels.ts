import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { Names } from "./catalog-functions.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, pageSize, userGrant } from "../shared.ts";
import { SLUG, catalogRank, guard } from "./catalog-functions.ts";

const LOCALE = /^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;

const LOCALE_SQL = "'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'";

/** `options.locales`, checked. The first is the default locale. */
export function catalogLocales(ctx: BlockSqlContext): readonly string[] {
  const locales = ctx.list("locales", ["en"]);

  if (locales.length === 0) {
    throw new TypeError(
      "blocks.catalog.options.locales must list at least one locale",
    );
  }

  for (const locale of locales) {
    if (!LOCALE.test(locale)) {
      throw new TypeError(
        `blocks.catalog.options.locales: "${locale}" is not a language tag such as "en" or "pt-BR"`,
      );
    }
  }

  if (new Set(locales).size !== locales.length) {
    throw new TypeError("blocks.catalog.options.locales lists a locale twice");
  }

  return locales;
}

/**
 * Whether a table added after version 2 exists: always when managed, and when
 * the app maps it on an adopted catalog.
 */
function catalogTable(ctx: BlockSqlContext, table: string): boolean {
  return ctx.hasTable(table) && (ctx.manages || !ctx.owns(table));
}

/** Product media needs the attachments module's table. */
function mediaOn(ctx: BlockSqlContext): boolean {
  return (
    catalogTable(ctx, "media") &&
    ctx.installed("attachments") &&
    ctx.of("attachments").mode !== "custom"
  );
}

const channelsOn = (ctx: BlockSqlContext): boolean =>
  catalogTable(ctx, "channels");

const listingsOn = (ctx: BlockSqlContext): boolean =>
  channelsOn(ctx) && catalogTable(ctx, "channelProducts");

const translationsOn = (ctx: BlockSqlContext): boolean =>
  catalogTable(ctx, "productTranslations");

const variantTranslationsOn = (ctx: BlockSqlContext): boolean =>
  catalogTable(ctx, "variantTranslations");

const priceListsOn = (ctx: BlockSqlContext): boolean =>
  ctx.hasTable("priceLists") && ctx.has("prices", "priceList");

interface Locales {
  /** The configured locales as a `text[]` literal. */
  readonly all: string;
  /** The default locale as a literal. */
  readonly fallback: string;
  /** `value` as a configured locale: itself, its language, or the default. */
  readonly resolve: (value: string) => string;
}

function localesOf(ctx: BlockSqlContext): Locales {
  const locales = catalogLocales(ctx);
  const all = `${sqlString(`{${locales.join(",")}}`)}::text[]`;
  const fallback = sqlString(locales[0] ?? "en");

  return {
    all,
    fallback,
    resolve: (value) =>
      `(case when ${value} = any (${all}) then ${value} when split_part(${value}, '-', 1) = any (${all}) then split_part(${value}, '-', 1) else ${fallback} end)`,
  };
}

/** A translation's locale: a configured one other than the default. */
function localeCheck(locales: Locales, value: string): string {
  return `if ${value} is null or not (${value} = any (${locales.all})) then
    ${fail("CATALOG_LOCALE_INVALID", "the locale is not one of blocks.catalog.options.locales", "22023")}
  end if;
  if ${value} = ${locales.fallback} then
    ${fail("CATALOG_LOCALE_DEFAULT", "the default locale's text lives on the record itself", "22023")}
  end if;`;
}

function readPolicy(ctx: BlockSqlContext, names: Names, table: string): string {
  const t = ctx.table(table);
  const policy = `${ctx.tableName(table).name}_read`;

  return renderPolicy(
    makePolicy({
      table: t,
      name: policy,
      command: "select",
      roles: ["authenticated"],
      using: `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`,
    }),
    { drop: true, target: t },
  );
}

/** The channel, translation and media tables (managed mode). */
export function channelTables(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages) {
    return "";
  }

  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);
  const lists = priceListsOn(ctx);
  const parts: string[] = [];

  if (channelsOn(ctx)) {
    parts.push(`
create table if not exists ${t("channels")} (
  ${c("channels", "id")} uuid primary key default gen_random_uuid(),
  ${c("channels", "tenant")} ${ctx.idType} not null,
  ${c("channels", "key")} text not null check (${c("channels", "key")} ~ ${SLUG}),
  ${c("channels", "name")} text not null check (length(${c("channels", "name")}) between 1 and 200),
  ${c("channels", "currency")} char(3) check (${c("channels", "currency")} ~ '^[A-Z]{3}$'),
  ${c("channels", "priceList")} uuid${lists ? ` references ${t("priceLists")} (${c("priceLists", "id")}) on delete set null` : ""},
  ${c("channels", "active")} boolean not null default true,
  ${c("channels", "createdAt")} timestamptz not null default now(),
  ${c("channels", "updatedAt")} timestamptz not null default now(),
  unique (${c("channels", "tenant")}, ${c("channels", "key")})
);${
      lists
        ? `
create index if not exists ${ctx.naming.rename("catalog_channels_price_list_idx")} on ${t("channels")} (${c("channels", "priceList")});`
        : ""
    }
${lockTable(t("channels"), { read: true })}
${readPolicy(ctx, names, "channels")}`);
  }

  if (listingsOn(ctx)) {
    parts.push(`
create table if not exists ${t("channelProducts")} (
  ${c("channelProducts", "tenant")} ${ctx.idType} not null,
  ${c("channelProducts", "channel")} uuid not null references ${t("channels")} (${c("channels", "id")}) on delete cascade,
  ${c("channelProducts", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("channelProducts", "listedAt")} timestamptz not null default now(),
  primary key (${c("channelProducts", "channel")}, ${c("channelProducts", "product")})
);
create index if not exists ${ctx.naming.rename("catalog_channel_products_product_idx")} on ${t("channelProducts")} (${c("channelProducts", "product")});
${lockTable(t("channelProducts"), { read: true })}
${readPolicy(ctx, names, "channelProducts")}`);
  }

  if (translationsOn(ctx)) {
    parts.push(`
create table if not exists ${t("productTranslations")} (
  ${c("productTranslations", "tenant")} ${ctx.idType} not null,
  ${c("productTranslations", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("productTranslations", "locale")} text not null check (${c("productTranslations", "locale")} ~ ${LOCALE_SQL}),
  ${c("productTranslations", "title")} text check (length(${c("productTranslations", "title")}) between 1 and 500),
  ${c("productTranslations", "description")} text,
  ${c("productTranslations", "updatedAt")} timestamptz not null default now(),
  primary key (${c("productTranslations", "product")}, ${c("productTranslations", "locale")})
);
${lockTable(t("productTranslations"), { read: true })}
${readPolicy(ctx, names, "productTranslations")}`);
  }

  if (variantTranslationsOn(ctx)) {
    parts.push(`
create table if not exists ${t("variantTranslations")} (
  ${c("variantTranslations", "tenant")} ${ctx.idType} not null,
  ${c("variantTranslations", "variant")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("variantTranslations", "locale")} text not null check (${c("variantTranslations", "locale")} ~ ${LOCALE_SQL}),
  ${c("variantTranslations", "title")} text check (length(${c("variantTranslations", "title")}) between 1 and 500),
  ${c("variantTranslations", "updatedAt")} timestamptz not null default now(),
  primary key (${c("variantTranslations", "variant")}, ${c("variantTranslations", "locale")})
);
${lockTable(t("variantTranslations"), { read: true })}
${readPolicy(ctx, names, "variantTranslations")}`);
  }

  if (mediaOn(ctx)) {
    const at = ctx.of("attachments");

    parts.push(`
create table if not exists ${t("media")} (
  ${c("media", "id")} uuid primary key default gen_random_uuid(),
  ${c("media", "tenant")} ${ctx.idType} not null,
  ${c("media", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("media", "variant")} uuid references ${t("variants")} (${c("variants", "id")}) on delete set null,
  ${c("media", "attachment")} uuid not null references ${at.table("attachments")} (${at.col("attachments", "id")}) on delete cascade,
  ${c("media", "position")} integer not null check (${c("media", "position")} >= 0),
  ${c("media", "alt")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${c("media", "alt")}) = 'object'),
  ${c("media", "createdAt")} timestamptz not null default now(),
  unique (${c("media", "product")}, ${c("media", "attachment")})
);
create index if not exists ${ctx.naming.rename("product_media_position_idx")} on ${t("media")} (${c("media", "product")}, ${c("media", "position")});
create index if not exists ${ctx.naming.rename("product_media_attachment_idx")} on ${t("media")} (${c("media", "attachment")});
create index if not exists ${ctx.naming.rename("product_media_variant_idx")} on ${t("media")} (${c("media", "variant")});
${lockTable(t("media"), { read: true })}
${readPolicy(ctx, names, "media")}`);
  }

  return parts.join("\n");
}

/** `[table, condition]` of the new tables a public storefront exposes. */
export function channelStorefrontTables(
  ctx: BlockSqlContext,
  names: Names,
): readonly (readonly [string, string])[] {
  const c = (table: string, column: string): string => ctx.col(table, column);
  const products = `select ${names.fn("storefront_products")}()`;
  const entries: (readonly [string, string])[] = [];

  if (channelsOn(ctx)) {
    entries.push([
      "channels",
      `${c("channels", "active")} and ${c("channels", "tenant")} in (select ${names.fn("storefront_tenants")}())`,
    ]);
  }

  if (listingsOn(ctx)) {
    entries.push([
      "channelProducts",
      `${c("channelProducts", "product")} in (${products}) and ${c("channelProducts", "channel")} in (select k.${c("channels", "id")} from ${ctx.table("channels")} k where k.${c("channels", "active")})`,
    ]);
  }

  if (translationsOn(ctx)) {
    entries.push([
      "productTranslations",
      `${c("productTranslations", "product")} in (${products})`,
    ]);
  }

  if (variantTranslationsOn(ctx)) {
    entries.push([
      "variantTranslations",
      `${c("variantTranslations", "variant")} in (select v.${c("variants", "id")} from ${ctx.table("variants")} v where v.${c("variants", "product")} in (${products}))`,
    ]);
  }

  if (mediaOn(ctx)) {
    entries.push(["media", `${c("media", "product")} in (${products})`]);
  }

  return entries;
}

/** Grants a read function to the storefront's `anon` as well. */
const readGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public;
grant execute on function ${signature} to anon, authenticated, service_role;`;

function channelFunctions(ctx: BlockSqlContext, names: Names): string {
  if (!channelsOn(ctx)) {
    return "";
  }

  const { fn } = names;
  const channels = ctx.table("channels");
  const k = (column: string): string => ctx.col("channels", column);
  const currency = ctx.has("channels", "currency");
  const lists = priceListsOn(ctx) && ctx.has("channels", "priceList");

  const columns = [
    k("key"),
    k("name"),
    ...(currency ? [k("currency")] : []),
    ...(lists ? [k("priceList")] : []),
    k("active"),
  ];

  const values = [
    "save_catalog_channel.key",
    "save_catalog_channel.name",
    ...(currency ? ["save_catalog_channel.currency"] : []),
    ...(lists ? ["save_catalog_channel.price_list"] : []),
    "coalesce(save_catalog_channel.active, true)",
  ];

  const sets = [
    `${k("key")} = save_catalog_channel.key`,
    `${k("name")} = save_catalog_channel.name`,
    ...(currency ? [`${k("currency")} = save_catalog_channel.currency`] : []),
    ...(lists ? [`${k("priceList")} = save_catalog_channel.price_list`] : []),
    `${k("active")} = coalesce(save_catalog_channel.active, x.${k("active")})`,
    `${k("updatedAt")} = now()`,
  ];

  const priceLists = lists ? ctx.table("priceLists") : "";
  const pl = (column: string): string => ctx.col("priceLists", column);

  const listings = listingsOn(ctx) ? listingFunctions(ctx, names) : "";

  const channelPrice = currency
    ? `
-- The price a variant sells at on a channel: variant_price in the channel's
-- currency and price list. Null when the channel has no currency.
create or replace function ${fn("channel_price")}(channel uuid, variant uuid, as_of timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("variant_price")}($2, k.${k("currency")}, ${lists ? `k.${k("priceList")}` : "null"}, $3)
  from ${channels} k
  where k.${k("id")} = $1 and k.${k("currency")} is not null
$$;
${readGrant(`${fn("channel_price")}(uuid, uuid, timestamptz)`)}
`
    : "";

  return `
-- Creates a sales channel (channel null) or updates one. A channel has a
-- key, unique per organization, and optionally a currency and a price list
-- its prices come from.
create or replace function ${fn("save_catalog_channel")}(tenant ${ctx.idType}, channel uuid, key text, name text, currency text, price_list uuid, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := save_catalog_channel.channel;
  v_active boolean;
begin
  ${guard(names, "save_catalog_channel.tenant")}
  if save_catalog_channel.key is null or save_catalog_channel.key !~ ${SLUG} then
    ${fail("CATALOG_CHANNEL_KEY_INVALID", "the channel key must be lower-case letters, digits and hyphens", "22023")}
  end if;
  if save_catalog_channel.currency is not null and ${
    currency
      ? `${fn("currency_minor_units")}(save_catalog_channel.currency) is null`
      : "true"
  } then
    ${fail("CATALOG_CURRENCY_INVALID", currency ? "not an ISO 4217 currency code" : "this catalog's channels have no currency", "22023")}
  end if;
  if save_catalog_channel.price_list is not null and ${
    lists
      ? `not exists (select 1 from ${priceLists} x where x.${pl("id")} = save_catalog_channel.price_list and x.${pl("tenant")} = save_catalog_channel.tenant)`
      : "true"
  } then
    ${fail("CATALOG_PRICE_LIST_NOT_FOUND", "price list not found", "P0002")}
  end if;
  begin
    if v_id is null then
      insert into ${channels} as x (${k("tenant")}, ${columns.join(", ")})
      values (save_catalog_channel.tenant, ${values.join(", ")})
      returning x.${k("id")}, x.${k("active")} into v_id, v_active;
    else
      update ${channels} x set ${sets.join(", ")}
      where x.${k("id")} = v_id and x.${k("tenant")} = save_catalog_channel.tenant
      returning x.${k("active")} into v_active;
      if not found then
        ${fail("CATALOG_CHANNEL_NOT_FOUND", "channel not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_CHANNEL_TAKEN", "another channel has this key", "23505")}
  end;
  return jsonb_build_object('id', v_id, 'key', save_catalog_channel.key, 'active', v_active);
end;
$$;
${userGrant(`${fn("save_catalog_channel")}(${ctx.idType}, uuid, text, text, text, uuid, boolean)`)}

-- Deletes a channel and its listings.
create or replace function ${fn("delete_catalog_channel")}(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${k("tenant")} into v_tenant from ${channels} x where x.${k("id")} = delete_catalog_channel.channel;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${channels} x where x.${k("id")} = delete_catalog_channel.channel;
  return true;
end;
$$;
${userGrant(`${fn("delete_catalog_channel")}(uuid)`)}
${channelPrice}${listings}`;
}

function listingFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const channels = ctx.table("channels");
  const listings = ctx.table("channelProducts");
  const products = ctx.table("products");

  const translations = translationsOn(ctx)
    ? ctx.table("productTranslations")
    : "";

  const k = (column: string): string => ctx.col("channels", column);
  const l = (column: string): string => ctx.col("channelProducts", column);
  const p = (column: string): string => ctx.col("products", column);
  const tr = (column: string): string => ctx.col("productTranslations", column);
  const locales = localesOf(ctx);
  const locale = locales.resolve("$2");
  const desc = ctx.has("products", "description");
  const kind = ctx.has("products", "kind");

  const translated = translationsOn(ctx);
  const trDesc = translated && ctx.has("productTranslations", "description");

  const title = translated
    ? `coalesce(t.${tr("title")}, p.${p("title")})`
    : `p.${p("title")}`;

  const description = desc
    ? trDesc
      ? `coalesce(t.${tr("description")}, p.${p("description")})`
      : `p.${p("description")}`
    : "null";

  return `
-- Lists products on a channel (listed true) or takes them off it. Returns
-- how many listings changed.
create or replace function ${fn("set_channel_listing")}(channel uuid, products uuid[], listed boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_count integer;
begin
  select x.${k("tenant")} into v_tenant from ${channels} x where x.${k("id")} = set_channel_listing.channel for update;
  if v_tenant is null then
    ${fail("CATALOG_CHANNEL_NOT_FOUND", "channel not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if exists (
    select 1 from unnest(coalesce(set_channel_listing.products, '{}'::uuid[])) i
    where not exists (select 1 from ${products} x where x.${p("id")} = i and x.${p("tenant")} = v_tenant)
  ) then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  if coalesce(set_channel_listing.listed, true) then
    insert into ${listings} (${l("tenant")}, ${l("channel")}, ${l("product")})
    select distinct v_tenant, set_channel_listing.channel, i from unnest(coalesce(set_channel_listing.products, '{}'::uuid[])) i
    on conflict do nothing;
  else
    delete from ${listings} x
    where x.${l("channel")} = set_channel_listing.channel
      and x.${l("product")} = any (coalesce(set_channel_listing.products, '{}'::uuid[]));
  end if;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("set_channel_listing")}(uuid, uuid[], boolean)`)}

-- The products listed on a channel by slug, with their text in locale
-- (the default text where a translation is missing). after is the last
-- slug of the previous page. Runs as the caller, so the read policies
-- decide what it sees.
create or replace function ${fn("channel_products")}(channel uuid, locale text default null, page_size integer default null, after text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by slug collate "C"), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p.${p("id")},
      'slug', p.${p("slug")},
      'status', ${ctx.label("products", "status", `p.${p("status")}`)},
      'kind', ${kind ? `p.${p("kind")}` : "null"},
      'locale', ${locale},
      'title', ${title},
      'description', ${description},
      'listedAt', l.${l("listedAt")}
    ) as item, p.${p("slug")} as slug
    from ${listings} l
    join ${products} p on p.${p("id")} = l.${l("product")}${
      translated
        ? `
    left join ${translations} t on t.${tr("product")} = p.${p("id")} and t.${tr("locale")} = ${locale}`
        : ""
    }
    where l.${l("channel")} = $1
      and ($4 is null or p.${p("slug")} collate "C" > $4 collate "C")
    order by p.${p("slug")} collate "C"
    limit ${pageSize("$3", 100, 500)}
  ) items
$$;
${readGrant(`${fn("channel_products")}(uuid, text, integer, text)`)}
`;
}

function translationFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const tr = (column: string): string => ctx.col("productTranslations", column);
  const vt = (column: string): string => ctx.col("variantTranslations", column);
  const locales = localesOf(ctx);
  const locale = locales.resolve("$2");
  const translated = translationsOn(ctx);
  const variantsTranslated = variantTranslationsOn(ctx);
  const desc = ctx.has("products", "description");
  const trDesc = translated && ctx.has("productTranslations", "description");
  const variantTitle = ctx.has("variants", "title");

  const titleCheck = (
    value: string,
  ): string => `if ${value} is not null and length(${value}) not between 1 and 500 then
    ${fail("CATALOG_TITLE_INVALID", "a title has 1 to 500 characters", "22023")}
  end if;`;

  const productWrite = translated
    ? `
-- Sets a product's title and description in a locale other than the
-- default. Null text falls back to the default text; both null removes the
-- translation. Returns whether one is stored.
create or replace function ${fn("set_product_translation")}(product uuid, locale text, title text, description text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = set_product_translation.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  ${localeCheck(locales, "set_product_translation.locale")}
  ${titleCheck("set_product_translation.title")}${
    trDesc
      ? ""
      : `
  if set_product_translation.description is not null then
    ${fail("CATALOG_TRANSLATION_INVALID", "this catalog's translations have no description", "22023")}
  end if;`
  }
  if set_product_translation.title is null and set_product_translation.description is null then
    delete from ${ctx.table("productTranslations")} x
    where x.${tr("product")} = set_product_translation.product and x.${tr("locale")} = set_product_translation.locale;
    return false;
  end if;
  insert into ${ctx.table("productTranslations")} as x (${tr("tenant")}, ${tr("product")}, ${tr("locale")}, ${tr("title")}${trDesc ? `, ${tr("description")}` : ""})
  values (v_tenant, set_product_translation.product, set_product_translation.locale, set_product_translation.title${trDesc ? ", set_product_translation.description" : ""})
  on conflict (${tr("product")}, ${tr("locale")}) do update
    set ${tr("title")} = excluded.${tr("title")}${trDesc ? `, ${tr("description")} = excluded.${tr("description")}` : ""}, ${tr("updatedAt")} = now();
  return true;
end;
$$;
${userGrant(`${fn("set_product_translation")}(uuid, text, text, text)`)}
`
    : "";

  const variantWrite = variantsTranslated
    ? `
-- Sets a variant's title in a locale other than the default; a null title
-- removes the translation. Returns whether one is stored.
create or replace function ${fn("set_variant_translation")}(variant uuid, locale text, title text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select x.${v("tenant")} into v_tenant from ${variants} x where x.${v("id")} = set_variant_translation.variant for update;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  ${localeCheck(locales, "set_variant_translation.locale")}
  ${titleCheck("set_variant_translation.title")}
  if set_variant_translation.title is null then
    delete from ${ctx.table("variantTranslations")} x
    where x.${vt("variant")} = set_variant_translation.variant and x.${vt("locale")} = set_variant_translation.locale;
    return false;
  end if;
  insert into ${ctx.table("variantTranslations")} as x (${vt("tenant")}, ${vt("variant")}, ${vt("locale")}, ${vt("title")})
  values (v_tenant, set_variant_translation.variant, set_variant_translation.locale, set_variant_translation.title)
  on conflict (${vt("variant")}, ${vt("locale")}) do update
    set ${vt("title")} = excluded.${vt("title")}, ${vt("updatedAt")} = now();
  return true;
end;
$$;
${userGrant(`${fn("set_variant_translation")}(uuid, text, text)`)}
`
    : "";

  const title = translated
    ? `coalesce(t.${tr("title")}, p.${p("title")})`
    : `p.${p("title")}`;

  const description = desc
    ? trDesc
      ? `coalesce(t.${tr("description")}, p.${p("description")})`
      : `p.${p("description")}`
    : "null";

  const variantText = variantTitle
    ? variantsTranslated
      ? `coalesce((select y.${vt("title")} from ${ctx.table("variantTranslations")} y where y.${vt("variant")} = w.${v("id")} and y.${vt("locale")} = ${locale}), w.${v("title")})`
      : `w.${v("title")}`
    : "null";

  return `${productWrite}${variantWrite}
-- A product's text and its variants' titles in locale: the locale itself,
-- then its language, then the default locale's text on the product. Runs
-- as the caller, so the read policies decide what it sees.
create or replace function ${fn("product_text")}(product uuid, locale text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.${p("id")},
    'slug', p.${p("slug")},
    'locale', ${locale},
    'title', ${title},
    'description', ${description},
    'variants', coalesce((
      select jsonb_agg(jsonb_build_object('id', w.${v("id")}, 'sku', w.${v("sku")}, 'title', ${variantText}) order by ${catalogRank(ctx).order(`w.${v("rank")}`)}, w.${v("id")})
      from ${variants} w where w.${v("product")} = p.${p("id")}
    ), '[]'::jsonb)
  )
  from ${products} p${
    translated
      ? `
  left join ${ctx.table("productTranslations")} t on t.${tr("product")} = p.${p("id")} and t.${tr("locale")} = ${locale}`
      : ""
  }
  where p.${p("id")} = $1
$$;
${readGrant(`${fn("product_text")}(uuid, text)`)}
`;
}

function mediaFunctions(ctx: BlockSqlContext, names: Names): string {
  if (!mediaOn(ctx)) {
    return "";
  }

  const { fn } = names;
  const at = ctx.of("attachments");
  const a = (column: string): string => at.col("attachments", column);
  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const media = ctx.table("media");
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const m = (column: string): string => ctx.col("media", column);
  const locales = localesOf(ctx);
  const productType = sqlString(ctx.resolved.entityNaming.rename("product"));

  const variantType = sqlString(
    ctx.resolved.entityNaming.rename("product_variant"),
  );

  const altCheck = (
    value: string,
  ): string => `if ${value} is not null and (jsonb_typeof(${value}) <> 'object' or exists (
    select 1 from jsonb_each(${value}) e (key, value)
    where not (e.key = any (${locales.all})) or jsonb_typeof(e.value) <> 'string' or length(e.value #>> '{}') not between 1 and 1000
  )) then
    ${fail("CATALOG_MEDIA_ALT_INVALID", "alt maps configured locales to text of 1 to 1000 characters", "22023")}
  end if;`;

  const variantCheck = (
    variant: string,
    product: string,
  ): string => `if ${variant} is not null and not exists (select 1 from ${variants} x where x.${v("id")} = ${variant} and x.${v("product")} = ${product}) then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found on this product", "P0002")}
  end if;`;

  const compact = (
    product: string,
  ): string => `update ${media} x set ${m("position")} = s.n - 1
  from (select y.${m("id")} as id, row_number() over (order by y.${m("position")}, y.${m("createdAt")}, y.${m("id")}) as n from ${media} y where y.${m("product")} = ${product}) s
  where x.${m("id")} = s.id and x.${m("position")} <> s.n - 1;`;

  return `
-- Adds a file to a product's media, last. The attachment must belong to the
-- product or one of its variants. variant shows it for one variant; alt
-- maps configured locales to alt text.
create or replace function ${fn("add_product_media")}(product uuid, attachment uuid, variant uuid, alt jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_position integer;
  v_id uuid;
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = add_product_media.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  ${variantCheck("add_product_media.variant", "add_product_media.product")}
  if not exists (
    select 1 from ${at.table("attachments")} f
    where f.${a("id")} = add_product_media.attachment
      and f.${a("tenant")} = v_tenant
      and (
        (f.${a("subjectType")} = ${productType} and f.${a("subjectId")} = add_product_media.product::text)
        or (f.${a("subjectType")} = ${variantType} and f.${a("subjectId")} in (select w.${v("id")}::text from ${variants} w where w.${v("product")} = add_product_media.product))
      )
  ) then
    ${fail("CATALOG_MEDIA_ATTACHMENT_NOT_FOUND", "attach the file to the product or one of its variants first", "P0002")}
  end if;
  ${altCheck("add_product_media.alt")}
  select coalesce(max(x.${m("position")}) + 1, 0) into v_position from ${media} x where x.${m("product")} = add_product_media.product;
  begin
    insert into ${media} (${m("tenant")}, ${m("product")}, ${m("variant")}, ${m("attachment")}, ${m("position")}, ${m("alt")})
    values (v_tenant, add_product_media.product, add_product_media.variant, add_product_media.attachment, v_position, coalesce(add_product_media.alt, '{}'::jsonb))
    returning ${m("id")} into v_id;
  exception when unique_violation then
    ${fail("CATALOG_MEDIA_TAKEN", "the file is already in the product's media", "23505")}
  end;
  return jsonb_build_object('id', v_id, 'position', v_position);
end;
$$;
${userGrant(`${fn("add_product_media")}(uuid, uuid, uuid, jsonb)`)}

-- Replaces a media item's variant and alt text.
create or replace function ${fn("update_product_media")}(media uuid, variant uuid, alt jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_product uuid;
begin
  select x.${m("tenant")}, x.${m("product")} into v_tenant, v_product from ${media} x where x.${m("id")} = update_product_media.media for update;
  if v_tenant is null then
    ${fail("CATALOG_MEDIA_NOT_FOUND", "media item not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  ${variantCheck("update_product_media.variant", "v_product")}
  ${altCheck("update_product_media.alt")}
  update ${media} x set ${m("variant")} = update_product_media.variant, ${m("alt")} = coalesce(update_product_media.alt, '{}'::jsonb)
  where x.${m("id")} = update_product_media.media;
  return true;
end;
$$;
${userGrant(`${fn("update_product_media")}(uuid, uuid, jsonb)`)}

-- Puts a product's media in the order of media, which lists every item once.
create or replace function ${fn("reorder_product_media")}(product uuid, media uuid[])
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_order uuid[] := coalesce(reorder_product_media.media, '{}'::uuid[]);
begin
  select x.${p("tenant")} into v_tenant from ${products} x where x.${p("id")} = reorder_product_media.product for update;
  if v_tenant is null then
    ${fail("CATALOG_PRODUCT_NOT_FOUND", "product not found", "P0002")}
  end if;
  ${guard(names, "v_tenant")}
  if (select count(distinct i) from unnest(v_order) i) <> cardinality(v_order)
    or (select count(*) from ${media} x where x.${m("product")} = reorder_product_media.product) <> cardinality(v_order)
    or exists (select 1 from unnest(v_order) i where not exists (select 1 from ${media} x where x.${m("id")} = i and x.${m("product")} = reorder_product_media.product))
  then
    ${fail("CATALOG_MEDIA_ORDER_INVALID", "list every media item of the product once", "22023")}
  end if;
  update ${media} x set ${m("position")} = o.n - 1
  from unnest(v_order) with ordinality o (id, n)
  where x.${m("id")} = o.id;
  return true;
end;
$$;
${userGrant(`${fn("reorder_product_media")}(uuid, uuid[])`)}

-- Removes a media item (the attachment stays) and closes the gap.
create or replace function ${fn("remove_product_media")}(media uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_product uuid;
begin
  select x.${m("tenant")}, x.${m("product")} into v_tenant, v_product from ${media} x where x.${m("id")} = remove_product_media.media;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${media} x where x.${m("id")} = remove_product_media.media;
  ${compact("v_product")}
  return true;
end;
$$;
${userGrant(`${fn("remove_product_media")}(uuid)`)}

-- A product's media in order, with alt text in locale (the default
-- locale's where it has none). Runs as the caller.
create or replace function ${fn("product_media")}(product uuid, locale text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.${m("id")},
    'attachmentId', x.${m("attachment")},
    'variantId', x.${m("variant")},
    'position', x.${m("position")},
    'alt', coalesce(x.${m("alt")} ->> ${locales.resolve("$2")}, x.${m("alt")} ->> ${locales.fallback}),
    'altByLocale', x.${m("alt")}
  ) order by x.${m("position")}, x.${m("id")}), '[]'::jsonb)
  from ${media} x
  where x.${m("product")} = $1
$$;
${readGrant(`${fn("product_media")}(uuid, text)`)}
`;
}

/** The channel, translation and media functions. */
export function channelModuleFunctions(
  ctx: BlockSqlContext,
  names: Names,
): string {
  return `${channelFunctions(ctx, names)}${translationFunctions(ctx, names)}${mediaFunctions(ctx, names)}`;
}

/** The contract entries of the channel, translation and media functions. */
export function channelContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    ...(channelsOn(ctx)
      ? [
          {
            name: "save_catalog_channel",
            args: ["{id}", "uuid", "text", "text", "text", "uuid", "boolean"],
            returns: "jsonb",
          },
          {
            name: "delete_catalog_channel",
            args: ["uuid"],
            returns: "boolean",
          },
          ...(ctx.has("channels", "currency")
            ? [
                {
                  name: "channel_price",
                  args: ["uuid", "uuid", "timestamptz"],
                  returns: "jsonb",
                },
              ]
            : []),
        ]
      : []),
    ...(listingsOn(ctx)
      ? [
          {
            name: "set_channel_listing",
            args: ["uuid", "uuid[]", "boolean"],
            returns: "integer",
          },
          {
            name: "channel_products",
            args: ["uuid", "text", "integer", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(translationsOn(ctx)
      ? [
          {
            name: "set_product_translation",
            args: ["uuid", "text", "text", "text"],
            returns: "boolean",
          },
        ]
      : []),
    ...(variantTranslationsOn(ctx)
      ? [
          {
            name: "set_variant_translation",
            args: ["uuid", "text", "text"],
            returns: "boolean",
          },
        ]
      : []),
    { name: "product_text", args: ["uuid", "text"], returns: "jsonb" },
    ...(mediaOn(ctx)
      ? [
          {
            name: "add_product_media",
            args: ["uuid", "uuid", "uuid", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "update_product_media",
            args: ["uuid", "uuid", "jsonb"],
            returns: "boolean",
          },
          {
            name: "reorder_product_media",
            args: ["uuid", "uuid[]"],
            returns: "boolean",
          },
          { name: "remove_product_media", args: ["uuid"], returns: "boolean" },
          { name: "product_media", args: ["uuid", "text"], returns: "jsonb" },
        ]
      : []),
  ];
}
