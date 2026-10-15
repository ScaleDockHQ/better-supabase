import type { PromotionsEvents } from "../../blocks/promotions/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { lockTable, schemaPreamble } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { columns } from "./orders-shared.ts";
import {
  type PromotionsNames,
  codeFunctions,
  discountFunctions,
  promotionFunctions,
} from "./promotions-functions.ts";

const EVENTS: ModuleEvents<PromotionsEvents> = {
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

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_promotion_save",
    "after_promotion_save",
    "before_promotion_activate",
  ],
  tables: {
    promotions: {
      name: "promotions",
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

function tables(ctx: ModuleContext, names: PromotionsNames): string {
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
  const currency = (column: string, nullable: boolean): string =>
    `${column} char(3) ${nullable ? "" : "not null "}check (${column} ~ '^[A-Z]{3}$')`;
  return `
create table if not exists ${t("promotions")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("description")} text check (length(${p("description")}) <= 2000),
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
create index if not exists promotions_tenant_idx on ${t("promotions")} (${p("tenant")}, ${p("active")}, ${p("automatic")});
${lockTable(t("promotions"), { read: true })}
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
);
create index if not exists promotion_codes_promotion_idx on ${t("codes")} (${k("promotion")});
${lockTable(t("codes"), { read: true })}
${policy("codes", tenantRead("codes"))}

create table if not exists ${t("cartCodes")} (
  ${cc("tenant")} ${ctx.idType} not null,
  ${cc("cart")} uuid not null references ${orders.table("carts")} (${cart("id")}) on delete cascade,
  ${cc("code")} uuid not null references ${t("codes")} (${k("id")}) on delete cascade,
  ${cc("createdAt")} timestamptz not null default now(),
  primary key (${cc("cart")}, ${cc("code")})
);
create index if not exists cart_promotion_codes_code_idx on ${t("cartCodes")} (${cc("code")});
${lockTable(t("cartCodes"), { read: true })}
${policy("cartCodes", `${tenantRead("cartCodes")} or exists (select 1 from ${orders.table("carts")} x where x.${cart("id")} = ${cc("cart")} and x.${cart("user")} = (select auth.uid()))`)}

create table if not exists ${t("redemptions")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("promotion")} uuid not null references ${t("promotions")} (${p("id")}),
  ${r("code")} uuid references ${t("codes")} (${k("id")}) on delete set null,
  ${r("order")} uuid not null references ${orders.table("orders")} (${order("id")}) on delete cascade,
  ${r("customer")} uuid references auth.users (id) on delete set null,
  ${r("email")} text,
  ${currency(r("currency"), false)},
  ${r("amount")} bigint not null check (${r("amount")} >= 0),
  ${r("status")} text not null default 'redeemed' check (${r("status")} in ('redeemed', 'released')),
  ${r("createdAt")} timestamptz not null default now(),
  ${r("releasedAt")} timestamptz,
  unique (${r("order")}, ${r("promotion")})
);
create index if not exists promotion_redemptions_promotion_idx on ${t("redemptions")} (${r("promotion")}, ${r("status")});
create index if not exists promotion_redemptions_customer_idx on ${t("redemptions")} (${r("customer")});
create index if not exists promotion_redemptions_code_idx on ${t("redemptions")} (${r("code")});
${lockTable(t("redemptions"), { read: true })}
${policy("redemptions", `${tenantRead("redemptions")} or ${r("customer")} = (select auth.uid())`)}
`;
}

function namesOf(ctx: ModuleContext): PromotionsNames {
  return {
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", OPERATIONS["promotions.manage"]),
    read: ctx.permission("read", OPERATIONS["promotions.read"]),
  };
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const names = namesOf(ctx);
  return `${schemaPreamble(ctx)}
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.
${tables(ctx, names)}${promotionFunctions(ctx, names)}${codeFunctions(ctx, names)}${discountFunctions(ctx, names)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "save_promotion",
      args: ["{id}", "uuid", "jsonb"],
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
    {
      name: "apply_promotion_code",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "remove_promotion_code",
      args: ["uuid", "text"],
      returns: "boolean",
    },
  ];
}

export const PROMOTIONS: ModuleDefinition = {
  name: "promotions",
  title: "Promotions",
  description:
    "Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.",
  requires: ["tenant", "access", "catalog", "orders"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
