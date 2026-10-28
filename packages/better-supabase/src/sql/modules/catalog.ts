import type { CatalogEvents } from "../../blocks/catalog/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Names } from "./catalog-functions.ts";

import { sqlString } from "../../core/template.ts";
import { currencyMinorUnitsFunction } from "../money-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import {
  catalogLocales,
  channelContract,
  channelModuleFunctions,
  channelStorefrontTables,
  channelTables,
} from "./catalog-channels.ts";
import {
  SLUG,
  catalogRank,
  categoryExtras,
  optionFunctions,
  productExtras,
  productFunctions,
  productSettingTypes,
  variantExtras,
  storefrontOption,
} from "./catalog-functions.ts";
import {
  categoryFunctions,
  collectionFunctions,
  priceFunctions,
  storefrontFunctions,
} from "./catalog-merchandising.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<CatalogEvents> = {
  "product.created": {
    subject: "products",
    payload: ["organizationId", "id", "slug", "kind"],
  },
  "product.updated": {
    subject: "products",
    payload: ["organizationId", "id", "slug"],
  },
  "product.status_changed": {
    subject: "products",
    payload: ["organizationId", "id", "from", "to"],
  },
  "product.deleted": { subject: "products", payload: ["organizationId", "id"] },
  "variant.created": {
    subject: "variants",
    payload: ["organizationId", "id", "productId", "sku"],
  },
  "variant.updated": {
    subject: "variants",
    payload: ["organizationId", "id", "productId", "sku"],
  },
  "variant.deleted": {
    subject: "variants",
    payload: ["organizationId", "id", "productId"],
  },
  "catalog.price_changed": {
    subject: "prices",
    payload: [
      "organizationId",
      "id",
      "variantId",
      "priceListId",
      "currency",
      "amount",
      "previousAmount",
    ],
  },
  "storefront.published": {
    subject: "storefronts",
    payload: ["organizationId"],
  },
  "storefront.unpublished": {
    subject: "storefronts",
    payload: ["organizationId"],
  },
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    product: {
      table: "products",
      singular: "product",
      primary: true,
      subject: {
        title: "title",
        url: "/products/{slug}",
        permissions: { read: "read", write: "manage" },
        cascade: true,
        search: { title: "title", body: ["description", "slug"] },
      },
    },
    product_variant: {
      table: "variants",
      singular: "product_variant",
      subject: {
        title: "sku",
        permissions: { read: "read", write: "manage" },
        cascade: true,
        search: { title: "sku", body: ["title", "barcode"] },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_product_save",
    "after_product_save",
    "before_variant_save",
    "after_variant_save",
    "before_price_set",
    "after_price_set",
  ],
  options: [
    "storefront",
    "extraColumns",
    "variantExtraColumns",
    "categoryExtraColumns",
    "locales",
    "rankType",
    "variantInUse",
  ],
  tables: {
    products: {
      name: "products",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        slug: "slug",
        title: "title",
        description: "description",
        kind: "kind",
        status: "status",
        createdAt: "created_at",
        updatedAt: "updated_at",
        price: "price",
        currency: "currency",
        trackInventory: "track_inventory",
      },
      optional: ["description", "kind", "price", "currency", "trackInventory"],
      typed: ["status", "kind"],
    },
    options: {
      name: "product_options",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        product: "product_id",
        name: "name",
        rank: "rank",
      },
    },
    optionValues: {
      name: "product_option_values",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        option: "option_id",
        value: "value",
        rank: "rank",
      },
    },
    variants: {
      name: "product_variants",
      app: {
        unused: (ctx) =>
          typeof ctx.config.columns["variants"]?.["status"] === "string"
            ? []
            : ["status"],
      },
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        product: "product_id",
        sku: "sku",
        title: "title",
        barcode: "barcode",
        weight: "weight_grams",
        trackInventory: "track_inventory",
        allowBackorder: "allow_backorder",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
        price: "price",
        status: "status",
      },
      optional: [
        "title",
        "barcode",
        "weight",
        "trackInventory",
        "price",
        "status",
      ],
    },
    variantValues: {
      name: "product_variant_values",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        variant: "variant_id",
        value: "option_value_id",
      },
    },
    priceLists: {
      name: "price_lists",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        customerGroup: "customer_group",
        createdAt: "created_at",
      },
    },
    prices: {
      name: "product_prices",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        variant: "variant_id",
        priceList: "price_list_id",
        currency: "currency",
        amount: "amount",
        compareAt: "compare_at_amount",
        validFrom: "valid_from",
        validUntil: "valid_until",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["priceList", "compareAt", "validFrom", "validUntil"],
    },
    categories: {
      name: "categories",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        parent: "parent_id",
        name: "name",
        slug: "slug",
        description: "description",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    productCategories: {
      name: "product_categories",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        product: "product_id",
        category: "category_id",
      },
    },
    collections: {
      name: "product_collections",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        slug: "slug",
        kind: "kind",
        rule: "rule",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    collectionProducts: {
      name: "collection_products",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        collection: "collection_id",
        product: "product_id",
        rank: "rank",
      },
    },
    storefronts: {
      name: "storefronts",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: { tenant: "tenant_id", publishedAt: "published_at" },
    },
    channels: {
      name: "catalog_channels",
      lifecycle: tenantExport,
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        currency: "currency",
        priceList: "price_list_id",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["currency", "priceList"],
    },
    channelProducts: {
      name: "catalog_channel_products",
      lifecycle: tenantExport,
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        tenant: "tenant_id",
        channel: "channel_id",
        product: "product_id",
        listedAt: "listed_at",
      },
    },
    productTranslations: {
      name: "product_translations",
      lifecycle: tenantExport,
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        tenant: "tenant_id",
        product: "product_id",
        locale: "locale",
        title: "title",
        description: "description",
        updatedAt: "updated_at",
      },
      optional: ["description"],
    },
    variantTranslations: {
      name: "product_variant_translations",
      lifecycle: tenantExport,
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        tenant: "tenant_id",
        variant: "variant_id",
        locale: "locale",
        title: "title",
        updatedAt: "updated_at",
      },
    },
    media: {
      name: "product_media",
      lifecycle: tenantExport,
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        product: "product_id",
        variant: "variant_id",
        attachment: "attachment_id",
        position: "position",
        alt: "alt",
        createdAt: "created_at",
      },
    },
  },
  migrations: [
    {
      from: 1,
      description:
        "The collections table is product_collections, so it doesn't read as the collections block's table.",
      table: "collections",
      was: "collections",
    },
  ],
};

function tables(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages) {
    return "";
  }

  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);
  const rank = catalogRank(ctx);
  // Without a prices table, a variant's price is a column on it, with its
  // product's price as the fallback and the product's currency.
  const onVariant = !ctx.hasTable("prices");

  const productColumns = [
    ...(onVariant && ctx.has("products", "price")
      ? [
          `${c("products", "price")} bigint check (${c("products", "price")} >= 0)`,
        ]
      : []),
    ...(onVariant
      ? [
          `${c("products", "currency")} char(3) not null default 'EUR' check (${c("products", "currency")} ~ '^[A-Z]{3}$')`,
        ]
      : []),
    ...(!ctx.has("variants", "trackInventory") &&
    ctx.has("products", "trackInventory")
      ? [`${c("products", "trackInventory")} boolean not null default true`]
      : []),
  ]
    .map((column) => `\n  ${column},`)
    .join("");

  const variantColumns = [
    ...(ctx.has("variants", "trackInventory")
      ? [`${c("variants", "trackInventory")} boolean not null default true`]
      : []),
    ...(onVariant && ctx.has("variants", "price")
      ? [
          `${c("variants", "price")} bigint check (${c("variants", "price")} >= 0)`,
        ]
      : []),
  ]
    .map((column) => `\n  ${column},`)
    .join("");

  const read = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: `${c(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`,
      }),
      { drop: true, target: t(table) },
    );

  return `
create table if not exists ${t("products")} (
  ${c("products", "id")} uuid primary key default gen_random_uuid(),
  ${c("products", "tenant")} ${ctx.idType} not null,
  ${c("products", "slug")} text not null check (${c("products", "slug")} ~ ${SLUG}),
  ${c("products", "title")} text not null check (length(${c("products", "title")}) between 1 and 500),
  ${c("products", "description")} text,
  ${c("products", "kind")} text not null default 'physical' check (${c("products", "kind")} in ('physical', 'digital', 'service')),
  ${c("products", "status")} text not null default 'draft',${productColumns}
  ${c("products", "createdAt")} timestamptz not null default now(),
  ${c("products", "updatedAt")} timestamptz not null default now(),
  unique (${c("products", "tenant")}, ${c("products", "slug")})
);
create index if not exists ${ctx.naming.rename("products_status_idx")} on ${t("products")} (${c("products", "tenant")}, ${c("products", "status")});${addExtraColumns(t("products"), productExtras(ctx))}
${lockTable(t("products"), { read: true })}
${read("products")}

create table if not exists ${t("options")} (
  ${c("options", "id")} uuid primary key default gen_random_uuid(),
  ${c("options", "tenant")} ${ctx.idType} not null,
  ${c("options", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("options", "name")} text not null check (length(${c("options", "name")}) between 1 and 80),
  ${c("options", "rank")} ${rank.type} not null default ${rank.fallback},
  unique (${c("options", "product")}, ${c("options", "name")})
);
${lockTable(t("options"), { read: true })}
${read("options")}

create table if not exists ${t("optionValues")} (
  ${c("optionValues", "id")} uuid primary key default gen_random_uuid(),
  ${c("optionValues", "tenant")} ${ctx.idType} not null,
  ${c("optionValues", "option")} uuid not null references ${t("options")} (${c("options", "id")}) on delete cascade,
  ${c("optionValues", "value")} text not null check (length(${c("optionValues", "value")}) between 1 and 80),
  ${c("optionValues", "rank")} ${rank.type} not null default ${rank.fallback},
  unique (${c("optionValues", "option")}, ${c("optionValues", "value")})
);
${lockTable(t("optionValues"), { read: true })}
${read("optionValues")}

create table if not exists ${t("variants")} (
  ${c("variants", "id")} uuid primary key default gen_random_uuid(),
  ${c("variants", "tenant")} ${ctx.idType} not null,
  ${c("variants", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("variants", "sku")} text not null check (length(${c("variants", "sku")}) between 1 and 100),
  ${c("variants", "title")} text,
  ${c("variants", "barcode")} text,
  ${c("variants", "weight")} integer check (${c("variants", "weight")} >= 0),${variantColumns}
  ${c("variants", "allowBackorder")} boolean not null default false,
  ${c("variants", "rank")} ${rank.type} not null default ${rank.fallback},
  ${c("variants", "createdAt")} timestamptz not null default now(),
  ${c("variants", "updatedAt")} timestamptz not null default now(),
  unique (${c("variants", "tenant")}, ${c("variants", "sku")})
);
create index if not exists ${ctx.naming.rename("product_variants_product_idx")} on ${t("variants")} (${c("variants", "product")});${addExtraColumns(t("variants"), variantExtras(ctx))}
${lockTable(t("variants"), { read: true })}
${read("variants")}

create table if not exists ${t("variantValues")} (
  ${c("variantValues", "tenant")} ${ctx.idType} not null,
  ${c("variantValues", "variant")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("variantValues", "value")} uuid not null references ${t("optionValues")} (${c("optionValues", "id")}),
  primary key (${c("variantValues", "variant")}, ${c("variantValues", "value")})
);
create index if not exists ${ctx.naming.rename("product_variant_values_value_idx")} on ${t("variantValues")} (${c("variantValues", "value")});
${lockTable(t("variantValues"), { read: true })}
${read("variantValues")}

create table if not exists ${t("priceLists")} (
  ${c("priceLists", "id")} uuid primary key default gen_random_uuid(),
  ${c("priceLists", "tenant")} ${ctx.idType} not null,
  ${c("priceLists", "name")} text not null check (length(${c("priceLists", "name")}) between 1 and 200),
  ${c("priceLists", "customerGroup")} text,
  ${c("priceLists", "createdAt")} timestamptz not null default now(),
  unique (${c("priceLists", "tenant")}, ${c("priceLists", "name")})
);
${lockTable(t("priceLists"), { read: true })}
${read("priceLists")}

create table if not exists ${t("prices")} (
  ${c("prices", "id")} uuid primary key default gen_random_uuid(),
  ${c("prices", "tenant")} ${ctx.idType} not null,
  ${c("prices", "variant")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("prices", "priceList")} uuid references ${t("priceLists")} (${c("priceLists", "id")}) on delete cascade,
  ${c("prices", "currency")} char(3) not null check (${c("prices", "currency")} ~ '^[A-Z]{3}$'),
  ${c("prices", "amount")} bigint not null check (${c("prices", "amount")} >= 0),
  ${c("prices", "compareAt")} bigint check (${c("prices", "compareAt")} > ${c("prices", "amount")}),
  ${c("prices", "validFrom")} timestamptz,
  ${c("prices", "validUntil")} timestamptz check (${c("prices", "validUntil")} > ${c("prices", "validFrom")}),
  ${c("prices", "createdAt")} timestamptz not null default now(),
  ${c("prices", "updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("product_prices_variant_idx")} on ${t("prices")} (${c("prices", "variant")}, ${c("prices", "currency")});
create index if not exists ${ctx.naming.rename("product_prices_price_list_idx")} on ${t("prices")} (${c("prices", "priceList")});
${lockTable(t("prices"), { read: true })}
${read("prices")}

create table if not exists ${t("categories")} (
  ${c("categories", "id")} uuid primary key default gen_random_uuid(),
  ${c("categories", "tenant")} ${ctx.idType} not null,
  ${c("categories", "parent")} uuid references ${t("categories")} (${c("categories", "id")}),
  ${c("categories", "name")} text not null check (length(${c("categories", "name")}) between 1 and 200),
  ${c("categories", "slug")} text not null check (${c("categories", "slug")} ~ ${SLUG}),
  ${c("categories", "description")} text,
  ${c("categories", "rank")} ${rank.type} not null default ${rank.fallback},
  ${c("categories", "createdAt")} timestamptz not null default now(),
  ${c("categories", "updatedAt")} timestamptz not null default now(),
  unique (${c("categories", "tenant")}, ${c("categories", "slug")})
);
create index if not exists ${ctx.naming.rename("categories_parent_idx")} on ${t("categories")} (${c("categories", "parent")});${addExtraColumns(t("categories"), categoryExtras(ctx))}
${lockTable(t("categories"), { read: true })}
${read("categories")}

create table if not exists ${t("productCategories")} (
  ${c("productCategories", "tenant")} ${ctx.idType} not null,
  ${c("productCategories", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("productCategories", "category")} uuid not null references ${t("categories")} (${c("categories", "id")}) on delete cascade,
  primary key (${c("productCategories", "product")}, ${c("productCategories", "category")})
);
create index if not exists ${ctx.naming.rename("product_categories_category_idx")} on ${t("productCategories")} (${c("productCategories", "category")});
${lockTable(t("productCategories"), { read: true })}
${read("productCategories")}

create table if not exists ${t("collections")} (
  ${c("collections", "id")} uuid primary key default gen_random_uuid(),
  ${c("collections", "tenant")} ${ctx.idType} not null,
  ${c("collections", "title")} text not null check (length(${c("collections", "title")}) between 1 and 200),
  ${c("collections", "slug")} text not null check (${c("collections", "slug")} ~ ${SLUG}),
  ${c("collections", "kind")} text not null default 'manual' check (${c("collections", "kind")} in ('manual', 'rule')),
  ${c("collections", "rule")} jsonb,
  ${c("collections", "createdAt")} timestamptz not null default now(),
  ${c("collections", "updatedAt")} timestamptz not null default now(),
  unique (${c("collections", "tenant")}, ${c("collections", "slug")}),
  check ((${c("collections", "kind")} = 'rule') = (${c("collections", "rule")} is not null))
);
${lockTable(t("collections"), { read: true })}
${read("collections")}

create table if not exists ${t("collectionProducts")} (
  ${c("collectionProducts", "tenant")} ${ctx.idType} not null,
  ${c("collectionProducts", "collection")} uuid not null references ${t("collections")} (${c("collections", "id")}) on delete cascade,
  ${c("collectionProducts", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("collectionProducts", "rank")} ${rank.type} not null default ${rank.fallback},
  primary key (${c("collectionProducts", "collection")}, ${c("collectionProducts", "product")})
);
create index if not exists ${ctx.naming.rename("collection_products_product_idx")} on ${t("collectionProducts")} (${c("collectionProducts", "product")});
${lockTable(t("collectionProducts"), { read: true })}
${read("collectionProducts")}

create table if not exists ${t("storefronts")} (
  ${c("storefronts", "tenant")} ${ctx.idType} primary key,
  ${c("storefronts", "publishedAt")} timestamptz
);
${lockTable(t("storefronts"), { read: true })}
${read("storefronts")}
${channelTables(ctx, names)}
`;
}

/**
 * Anon read policies for active products of tenants with a published
 * storefront.
 */
function storefrontPolicies(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages) {
    return "";
  }

  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);

  const publicTables: readonly (readonly [string, string])[] = [
    [
      "products",
      `${ctx.is("products", "status", c("products", "status"), ["active"])} and ${c("products", "tenant")} in (select ${names.fn("storefront_tenants")}())`,
    ],
    [
      "options",
      `${c("options", "product")} in (select ${names.fn("storefront_products")}())`,
    ],
    [
      "optionValues",
      `${c("optionValues", "option")} in (select o.${c("options", "id")} from ${t("options")} o where o.${c("options", "product")} in (select ${names.fn("storefront_products")}()))`,
    ],
    [
      "variants",
      `${c("variants", "product")} in (select ${names.fn("storefront_products")}())`,
    ],
    [
      "variantValues",
      `${c("variantValues", "variant")} in (select v.${c("variants", "id")} from ${t("variants")} v where v.${c("variants", "product")} in (select ${names.fn("storefront_products")}()))`,
    ],
    ...(ctx.hasTable("prices")
      ? ([
          [
            "prices",
            `${c("prices", "priceList")} is null and ${c("prices", "variant")} in (select v.${c("variants", "id")} from ${t("variants")} v where v.${c("variants", "product")} in (select ${names.fn("storefront_products")}()))`,
          ],
        ] as const)
      : []),
    [
      "categories",
      `${c("categories", "tenant")} in (select ${names.fn("storefront_tenants")}())`,
    ],
    [
      "productCategories",
      `${c("productCategories", "product")} in (select ${names.fn("storefront_products")}())`,
    ],
    [
      "collections",
      `${c("collections", "tenant")} in (select ${names.fn("storefront_tenants")}())`,
    ],
    [
      "collectionProducts",
      `${c("collectionProducts", "product")} in (select ${names.fn("storefront_products")}())`,
    ],
    ...channelStorefrontTables(ctx, names),
  ];

  const on = storefrontOption(ctx);

  return publicTables
    .map(([table, condition]) => {
      const policy = `${ctx.tableName(table).name}_storefront`;
      const drop = `drop policy if exists ${policy} on ${t(table)};`;

      if (!on) {
        return drop;
      }

      return `${drop}
grant select on ${t(table)} to anon;
${renderPolicy(makePolicy({ table: t(table), name: policy, command: "select", roles: ["anon", "authenticated"], using: condition }), { target: t(table) })}`;
    })
    .join("\n");
}

const actionKey = (
  ctx: BlockSqlContext,
  action: string,
  fallback: string,
): string =>
  sqlString(
    ctx.config.permissions[action] ?? ctx.permissionKey("manage", fallback),
  );

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("catalog");

  const names: Names = {
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", keys.manage),
    read: ctx.permission("read", keys.read),
    create: actionKey(ctx, "create", keys.manage),
    update: actionKey(ctx, "update", keys.manage),
    remove: actionKey(ctx, "delete", keys.manage),
  };

  storefrontOption(ctx);
  catalogLocales(ctx);

  return `${schemaPreamble(ctx)}
-- Products with options, variants and prices in minor units, plus
-- categories, collections, price lists, sales channels, translations,
-- product media and an optional public storefront.
${currencyMinorUnitsFunction(names.fn("currency_minor_units"))}
${tables(ctx, names)}${productFunctions(ctx, names)}${optionFunctions(ctx, names)}${priceFunctions(ctx, names)}${categoryFunctions(ctx, names)}${collectionFunctions(ctx, names)}${storefrontFunctions(ctx, names)}${channelModuleFunctions(ctx, names)}
${ctx.hasTable("storefronts") ? storefrontPolicies(ctx, names) : ""}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const options = ctx.hasTable("options") && ctx.hasTable("optionValues");
  const lists = ctx.hasTable("priceLists") && ctx.has("prices", "priceList");

  return [
    { name: "currency_minor_units", args: ["text"], returns: "integer" },
    {
      name: "save_product",
      args: [
        "{id}",
        "uuid",
        "text",
        "text",
        "text",
        "text",
        ...productSettingTypes(ctx),
        "text[]",
        ...extraFieldsArg(productExtras(ctx)).contract,
      ],
      returns: "jsonb",
    },
    { name: "set_product_status", args: ["uuid", "text"], returns: "jsonb" },
    { name: "delete_product", args: ["uuid"], returns: "boolean" },
    ...(options
      ? [
          {
            name: "save_product_option",
            args: ["uuid", "uuid", "text", "text[]"],
            returns: "jsonb",
          },
          { name: "delete_product_option", args: ["uuid"], returns: "boolean" },
          {
            name: "reorder_product_options",
            args: ["uuid", "uuid[]"],
            returns: "boolean",
          },
        ]
      : []),
    {
      name: "save_variant",
      args: [
        "uuid",
        "uuid",
        "text",
        "uuid[]",
        "text",
        "text",
        "integer",
        "boolean",
        "boolean",
        "text[]",
        ...extraFieldsArg(variantExtras(ctx)).contract,
      ],
      returns: "jsonb",
    },
    { name: "rank_variant", args: ["uuid", "text"], returns: "boolean" },
    { name: "delete_variant", args: ["uuid"], returns: "boolean" },
    ...(lists
      ? [
          {
            name: "save_price_list",
            args: ["{id}", "uuid", "text", "text"],
            returns: "jsonb",
          },
          { name: "delete_price_list", args: ["uuid"], returns: "boolean" },
        ]
      : []),
    {
      name: "set_price",
      args: [
        "uuid",
        "text",
        "text",
        "text",
        "uuid",
        "timestamptz",
        "timestamptz",
      ],
      returns: "jsonb",
    },
    { name: "delete_price", args: ["uuid"], returns: "boolean" },
    {
      name: "variant_price",
      args: ["uuid", "text", "uuid", "timestamptz"],
      returns: "jsonb",
    },
    ...(ctx.hasTable("categories")
      ? [
          {
            name: "save_category",
            args: [
              "{id}",
              "uuid",
              "uuid",
              "text",
              "text",
              "text",
              ...extraFieldsArg(categoryExtras(ctx)).contract,
            ],
            returns: "jsonb",
          },
          {
            name: "move_category",
            args: ["uuid", "uuid", "text"],
            returns: "boolean",
          },
          { name: "delete_category", args: ["uuid"], returns: "boolean" },
          ...(ctx.hasTable("productCategories")
            ? [
                {
                  name: "set_product_categories",
                  args: ["uuid", "uuid[]"],
                  returns: "boolean",
                },
              ]
            : []),
        ]
      : []),
    ...(ctx.hasTable("collections")
      ? [
          {
            name: "save_collection",
            args: ["{id}", "uuid", "text", "text", "text", "jsonb"],
            returns: "jsonb",
          },
          { name: "delete_collection", args: ["uuid"], returns: "boolean" },
          ...(ctx.hasTable("collectionProducts")
            ? [
                {
                  name: "add_to_collection",
                  args: ["uuid", "uuid", "text"],
                  returns: "text",
                },
                {
                  name: "remove_from_collection",
                  args: ["uuid", "uuid"],
                  returns: "boolean",
                },
              ]
            : []),
        ]
      : []),
    ...(ctx.hasTable("storefronts")
      ? [
          {
            name: "publish_storefront",
            args: ["{id}", "boolean"],
            returns: "boolean",
          },
        ]
      : []),
    ...channelContract(ctx),
  ];
}

export const CATALOG: BlockSqlDefinition = {
  name: "catalog",
  scopes: ["tenant"],
  title: "Catalog",
  description:
    "Products with options, variants and prices in minor units, price lists, a category tree, collections, sales channels, translations per locale, product media and an optional public storefront.",
  requires: ["memberships", "permissions"],
  before: "search",
  integrates: ["outbox", "state-machine", "inventory", "attachments"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  names: NAMES,
  upgrades: [
    {
      from: 2,
      description:
        "Sales channels with product listings, translations per locale and, with attachments, product media.",
      sql: () => "",
    },
  ],
  contract,
  build,
};
