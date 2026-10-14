import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { currencyMinorUnitsFunction } from "../money-sql.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import {
  type Names,
  SLUG,
  optionFunctions,
  productFunctions,
  storefrontOption,
} from "./catalog-functions.ts";
import {
  categoryFunctions,
  collectionFunctions,
  priceFunctions,
  storefrontFunctions,
} from "./catalog-merchandising.ts";

const EVENTS: ModuleEvents = {
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
  "product.deleted": {
    subject: "products",
    payload: ["organizationId", "id"],
  },
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

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_product_save",
    "after_product_save",
    "before_variant_save",
    "after_variant_save",
    "before_price_set",
    "after_price_set",
  ],
  options: ["storefront"],
  tables: {
    products: {
      name: "products",
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
      },
      optional: ["description", "kind"],
    },
    options: {
      name: "product_options",
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
      },
      optional: ["title", "barcode", "weight"],
    },
    variantValues: {
      name: "product_variant_values",
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
      lifecycle: tenantExport,
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
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        product: "product_id",
        category: "category_id",
      },
    },
    collections: {
      name: "collections",
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
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        publishedAt: "published_at",
      },
    },
  },
};

function tables(ctx: ModuleContext, names: Names): string {
  if (!ctx.manages) return "";
  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);
  const read = (
    table: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${c(table, "tenant")} in (select better_supabase.tenant_ids_with(${names.read})));`;
  return `
create table if not exists ${t("products")} (
  ${c("products", "id")} uuid primary key default gen_random_uuid(),
  ${c("products", "tenant")} ${ctx.idType} not null,
  ${c("products", "slug")} text not null check (${c("products", "slug")} ~ ${SLUG}),
  ${c("products", "title")} text not null check (length(${c("products", "title")}) between 1 and 500),
  ${c("products", "description")} text,
  ${c("products", "kind")} text not null default 'physical' check (${c("products", "kind")} in ('physical', 'digital', 'service')),
  ${c("products", "status")} text not null default 'draft',
  ${c("products", "createdAt")} timestamptz not null default now(),
  ${c("products", "updatedAt")} timestamptz not null default now(),
  unique (${c("products", "tenant")}, ${c("products", "slug")})
);
create index if not exists products_status_idx on ${t("products")} (${c("products", "tenant")}, ${c("products", "status")});
${lockTable(t("products"), { read: true })}
${read("products")}

create table if not exists ${t("options")} (
  ${c("options", "id")} uuid primary key default gen_random_uuid(),
  ${c("options", "tenant")} ${ctx.idType} not null,
  ${c("options", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("options", "name")} text not null check (length(${c("options", "name")}) between 1 and 80),
  ${c("options", "rank")} text collate "C" not null default 'V',
  unique (${c("options", "product")}, ${c("options", "name")})
);
${lockTable(t("options"), { read: true })}
${read("options")}

create table if not exists ${t("optionValues")} (
  ${c("optionValues", "id")} uuid primary key default gen_random_uuid(),
  ${c("optionValues", "tenant")} ${ctx.idType} not null,
  ${c("optionValues", "option")} uuid not null references ${t("options")} (${c("options", "id")}) on delete cascade,
  ${c("optionValues", "value")} text not null check (length(${c("optionValues", "value")}) between 1 and 80),
  ${c("optionValues", "rank")} text collate "C" not null default 'V',
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
  ${c("variants", "weight")} integer check (${c("variants", "weight")} >= 0),
  ${c("variants", "trackInventory")} boolean not null default true,
  ${c("variants", "allowBackorder")} boolean not null default false,
  ${c("variants", "rank")} text collate "C" not null default 'V',
  ${c("variants", "createdAt")} timestamptz not null default now(),
  ${c("variants", "updatedAt")} timestamptz not null default now(),
  unique (${c("variants", "tenant")}, ${c("variants", "sku")})
);
create index if not exists product_variants_product_idx on ${t("variants")} (${c("variants", "product")});
${lockTable(t("variants"), { read: true })}
${read("variants")}

create table if not exists ${t("variantValues")} (
  ${c("variantValues", "tenant")} ${ctx.idType} not null,
  ${c("variantValues", "variant")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("variantValues", "value")} uuid not null references ${t("optionValues")} (${c("optionValues", "id")}),
  primary key (${c("variantValues", "variant")}, ${c("variantValues", "value")})
);
create index if not exists product_variant_values_value_idx on ${t("variantValues")} (${c("variantValues", "value")});
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
create index if not exists product_prices_variant_idx on ${t("prices")} (${c("prices", "variant")}, ${c("prices", "currency")});
create index if not exists product_prices_price_list_idx on ${t("prices")} (${c("prices", "priceList")});
${lockTable(t("prices"), { read: true })}
${read("prices")}

create table if not exists ${t("categories")} (
  ${c("categories", "id")} uuid primary key default gen_random_uuid(),
  ${c("categories", "tenant")} ${ctx.idType} not null,
  ${c("categories", "parent")} uuid references ${t("categories")} (${c("categories", "id")}),
  ${c("categories", "name")} text not null check (length(${c("categories", "name")}) between 1 and 200),
  ${c("categories", "slug")} text not null check (${c("categories", "slug")} ~ ${SLUG}),
  ${c("categories", "description")} text,
  ${c("categories", "rank")} text collate "C" not null default 'V',
  ${c("categories", "createdAt")} timestamptz not null default now(),
  ${c("categories", "updatedAt")} timestamptz not null default now(),
  unique (${c("categories", "tenant")}, ${c("categories", "slug")})
);
create index if not exists categories_parent_idx on ${t("categories")} (${c("categories", "parent")});
${lockTable(t("categories"), { read: true })}
${read("categories")}

create table if not exists ${t("productCategories")} (
  ${c("productCategories", "tenant")} ${ctx.idType} not null,
  ${c("productCategories", "product")} uuid not null references ${t("products")} (${c("products", "id")}) on delete cascade,
  ${c("productCategories", "category")} uuid not null references ${t("categories")} (${c("categories", "id")}) on delete cascade,
  primary key (${c("productCategories", "product")}, ${c("productCategories", "category")})
);
create index if not exists product_categories_category_idx on ${t("productCategories")} (${c("productCategories", "category")});
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
  ${c("collectionProducts", "rank")} text collate "C" not null default 'V',
  primary key (${c("collectionProducts", "collection")}, ${c("collectionProducts", "product")})
);
create index if not exists collection_products_product_idx on ${t("collectionProducts")} (${c("collectionProducts", "product")});
${lockTable(t("collectionProducts"), { read: true })}
${read("collectionProducts")}

create table if not exists ${t("storefronts")} (
  ${c("storefronts", "tenant")} ${ctx.idType} primary key,
  ${c("storefronts", "publishedAt")} timestamptz
);
${lockTable(t("storefronts"), { read: true })}
${read("storefronts")}
`;
}

/** Anon read policies for active products of tenants with a published storefront. */
function storefrontPolicies(ctx: ModuleContext, names: Names): string {
  if (!ctx.manages) return "";
  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);
  const publicTables: readonly (readonly [string, string])[] = [
    [
      "products",
      `${c("products", "status")} = 'active' and ${c("products", "tenant")} in (select ${names.fn("storefront_tenants")}())`,
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
    [
      "prices",
      `${c("prices", "priceList")} is null and ${c("prices", "variant")} in (select v.${c("variants", "id")} from ${t("variants")} v where v.${c("variants", "product")} in (select ${names.fn("storefront_products")}()))`,
    ],
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
  ];
  const on = storefrontOption(ctx);
  return publicTables
    .map(([table, condition]) => {
      const policy = `${ctx.tableName(table).name}_storefront`;
      const drop = `drop policy if exists ${policy} on ${t(table)};`;
      if (!on) return drop;
      return `${drop}
grant select on ${t(table)} to anon;
create policy ${policy} on ${t(table)} for select to anon, authenticated
using (${condition});`;
    })
    .join("\n");
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const keys = moduleOperations("catalog");
  const names: Names = {
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", keys.manage),
    read: ctx.permission("read", keys.read),
  };
  storefrontOption(ctx);
  return `${schemaPreamble(ctx)}
-- Products with options, variants and prices in minor units, plus
-- categories, collections, price lists and an optional public storefront.
${currencyMinorUnitsFunction(names.fn("currency_minor_units"))}
${tables(ctx, names)}${productFunctions(ctx, names)}${optionFunctions(ctx, names)}${priceFunctions(ctx, names)}${categoryFunctions(ctx, names)}${collectionFunctions(ctx, names)}${storefrontFunctions(ctx, names)}
${ctx.hasTable("storefronts") ? storefrontPolicies(ctx, names) : ""}
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const options = ctx.hasTable("options") && ctx.hasTable("optionValues");
  const lists = ctx.hasTable("priceLists") && ctx.has("prices", "priceList");
  return [
    { name: "currency_minor_units", args: ["text"], returns: "integer" },
    {
      name: "save_product",
      args: ["{id}", "uuid", "text", "text", "text", "text"],
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
            args: ["{id}", "uuid", "uuid", "text", "text", "text"],
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
  ];
}

export const CATALOG: ModuleDefinition = {
  name: "catalog",
  title: "Catalog",
  description:
    "Products with options, variants and prices in minor units, price lists, a category tree, collections and an optional public storefront.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "state-machine", "inventory"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
