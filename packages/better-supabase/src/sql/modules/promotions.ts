import type { PromotionsEvents } from "../../blocks/promotions/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { PromotionsNames } from "./promotions-functions.ts";

import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { columns } from "./orders-shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { OPERATIONS } from "./permissions-model.ts";
import {
  codeFunctions,
  discountFunctions,
  promotionExtras,
  promotionFunctions,
} from "./promotions-functions.ts";

const EVENTS: BlockSqlEvents<PromotionsEvents> = {
  "promotion.redeemed": {
    subject: "promotion-redemptions",
    payload: [
      "organizationId",
      "id",
      "promotionId",
      "code",
      "orderId",
      "currency",
      "amount",
    ],
  },
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    promotion: { table: "promotions", singular: "promotion", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_promotion_save",
    "after_promotion_save",
    "before_promotion_activate",
  ],
  options: ["extraColumns"],
  tables: {
    promotions: {
      name: "promotions",
      app: {},
      optional: ["description"],
      typed: ["kind", "scope"],
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        description: "description",
        kind: "kind",
        percent: "percent",
        currency: "currency",
        amount: "amount",
        minSubtotal: "min_subtotal",
        scope: "scope",
        targets: "target_ids",
        startsAt: "starts_at",
        endsAt: "ends_at",
        usageLimit: "usage_limit",
        perCustomerLimit: "per_customer_limit",
        redemptions: "redemptions",
        stackable: "stackable",
        priority: "priority",
        automatic: "automatic",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    codes: {
      name: "promotion_codes",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        promotion: "promotion_id",
        code: "code",
        usageLimit: "usage_limit",
        redemptions: "redemptions",
        createdAt: "created_at",
      },
    },
    cartCodes: {
      name: "cart_promotion_codes",
      app: {},
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        cart: "cart_id",
        code: "code_id",
        createdAt: "created_at",
      },
    },
    redemptions: {
      name: "promotion_redemptions",
      app: {},
      optional: ["email", "releasedAt"],
      typed: ["status"],
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        promotion: "promotion_id",
        code: "code_id",
        order: "order_id",
        customer: "customer_id",
        email: "email",
        currency: "currency",
        amount: "amount",
        status: "status",
        createdAt: "created_at",
        releasedAt: "released_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext, names: PromotionsNames): string {
  const orders = ctx.of("orders");
  const t = (name: string): string => ctx.table(name);
  const p = columns(ctx, "promotions");
  const k = columns(ctx, "codes");
  const cc = columns(ctx, "cartCodes");
  const r = columns(ctx, "redemptions");
  const cart = columns(orders, "carts");
  const order = columns(orders, "orders");

  const tenantRead = (table: string): string =>
    `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`;

  const policy = (
    table: string,
    using: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${using});`;

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const currency = (column: string, nullable: boolean): string =>
    `${column} char(3) ${nullable ? "" : "not null "}check (${column} ~ '^[A-Z]{3}$')`;

  return `
create table if not exists ${t("promotions")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),${column("promotions", "description", (name) => `${name} text check (length(${name}) <= 2000)`)}
  ${p("kind")} text not null check (${p("kind")} in ('percentage', 'fixed', 'free_shipping')),
  ${p("percent")} numeric(5, 2) check (${p("percent")} > 0 and ${p("percent")} <= 100),
  ${currency(p("currency"), true)},
  ${p("amount")} bigint check (${p("amount")} > 0),
  ${p("minSubtotal")} bigint check (${p("minSubtotal")} > 0),
  ${p("scope")} text not null default 'order' check (${p("scope")} in ('order', 'products', 'categories', 'collections')),
  ${p("targets")} uuid[] not null default '{}',
  ${p("startsAt")} timestamptz,
  ${p("endsAt")} timestamptz,
  ${p("usageLimit")} integer check (${p("usageLimit")} > 0),
  ${p("perCustomerLimit")} integer check (${p("perCustomerLimit")} > 0),
  ${p("redemptions")} integer not null default 0 check (${p("redemptions")} >= 0),
  ${p("stackable")} boolean not null default false,
  ${p("priority")} integer not null default 0,
  ${p("automatic")} boolean not null default false,
  ${p("active")} boolean not null default true,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  check ((${p("kind")} = 'percentage') = (${p("percent")} is not null)),
  check ((${p("kind")} = 'fixed') = (${p("amount")} is not null)),
  check ((${p("amount")} is null and ${p("minSubtotal")} is null) or ${p("currency")} is not null),
  check (${p("endsAt")} is null or ${p("startsAt")} is null or ${p("endsAt")} > ${p("startsAt")})
);
create index if not exists ${ctx.naming.rename("promotions_tenant_idx")} on ${t("promotions")} (${p("tenant")}, ${p("active")}, ${p("automatic")});${addExtraColumns(t("promotions"), promotionExtras(ctx))}
${lockModuleTable(ctx, "promotions", { read: true })}
${policy("promotions", tenantRead("promotions"))}

create table if not exists ${t("codes")} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("promotion")} uuid not null references ${t("promotions")} (${p("id")}) on delete cascade,
  ${k("code")} text not null check (${k("code")} ~ '^[A-Z0-9_-]{3,40}$'),
  ${k("usageLimit")} integer check (${k("usageLimit")} > 0),
  ${k("redemptions")} integer not null default 0 check (${k("redemptions")} >= 0),
  ${k("createdAt")} timestamptz not null default now(),
  unique (${k("tenant")}, ${k("code")})
);${appUniqueIndex(ctx, "codes", ["tenant", "code"])}
create index if not exists ${ctx.naming.rename("promotion_codes_promotion_idx")} on ${t("codes")} (${k("promotion")});
${lockModuleTable(ctx, "codes", { read: true })}
${policy("codes", tenantRead("codes"))}

create table if not exists ${t("cartCodes")} (
  ${cc("tenant")} ${ctx.idType} not null,
  ${cc("cart")} uuid not null references ${orders.table("carts")} (${cart("id")}) on delete cascade,
  ${cc("code")} uuid not null references ${t("codes")} (${k("id")}) on delete cascade,
  ${cc("createdAt")} timestamptz not null default now(),
  primary key (${cc("cart")}, ${cc("code")})
);${appUniqueIndex(ctx, "cartCodes", ["cart", "code"])}
create index if not exists ${ctx.naming.rename("cart_promotion_codes_code_idx")} on ${t("cartCodes")} (${cc("code")});
${lockModuleTable(ctx, "cartCodes", { read: true })}
${policy("cartCodes", `${tenantRead("cartCodes")} or exists (select 1 from ${orders.table("carts")} x where x.${cart("id")} = ${cc("cart")} and x.${cart("user")} = (select auth.uid()))`)}

create table if not exists ${t("redemptions")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("promotion")} uuid not null references ${t("promotions")} (${p("id")}),
  ${r("code")} uuid references ${t("codes")} (${k("id")}) on delete set null,
  ${r("order")} uuid not null references ${orders.table("orders")} (${order("id")}) on delete cascade,
  ${r("customer")} uuid references auth.users (id) on delete set null,${column("redemptions", "email", (name) => `${name} text`)}
  ${currency(r("currency"), false)},
  ${r("amount")} bigint not null check (${r("amount")} >= 0),
  ${r("status")} text not null default 'redeemed' check (${r("status")} in ('redeemed', 'released')),
  ${r("createdAt")} timestamptz not null default now(),${column("redemptions", "releasedAt", (name) => `${name} timestamptz`)}
  unique (${r("order")}, ${r("promotion")})
);${appUniqueIndex(ctx, "redemptions", ["order", "promotion"])}
create index if not exists ${ctx.naming.rename("promotion_redemptions_promotion_idx")} on ${t("redemptions")} (${r("promotion")}, ${r("status")});
create index if not exists ${ctx.naming.rename("promotion_redemptions_customer_idx")} on ${t("redemptions")} (${r("customer")});
create index if not exists ${ctx.naming.rename("promotion_redemptions_code_idx")} on ${t("redemptions")} (${r("code")});
${lockModuleTable(ctx, "redemptions", { read: true })}
${policy("redemptions", `${tenantRead("redemptions")} or ${r("customer")} = (select auth.uid())`)}
`;
}

function namesOf(ctx: BlockSqlContext): PromotionsNames {
  return {
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", OPERATIONS["promotions.manage"]),
    read: ctx.permission("read", OPERATIONS["promotions.read"]),
  };
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names = namesOf(ctx);

  return `${schemaPreamble(ctx)}
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.
${tables(ctx, names)}${promotionFunctions(ctx, names)}${codeFunctions(ctx, names)}${discountFunctions(ctx, names)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_promotion",
      args: [
        "{id}",
        "uuid",
        "jsonb",
        ...extraFieldsArg(promotionExtras(ctx)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "set_promotion_active",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "delete_promotion", args: ["uuid"], returns: "boolean" },
    {
      name: "create_promotion_codes",
      args: ["uuid", "text[]", "integer", "text", "integer"],
      returns: "jsonb",
    },
    { name: "delete_promotion_code", args: ["uuid"], returns: "boolean" },
    { name: "apply_promotion_code", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "remove_promotion_code",
      args: ["uuid", "text"],
      returns: "boolean",
    },
  ];
}

export const PROMOTIONS: BlockSqlDefinition = {
  name: "promotions",
  scopes: ["tenant"],
  title: "Promotions",
  description:
    "Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.",
  requires: ["memberships", "permissions", "catalog", "orders"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
