import type { OrdersEvents } from "../../blocks/orders/events.ts";
import type { CommerceSubjectEventData } from "../../core/block-events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { BILLING_PARTIES, COST_SOURCES } from "../line-items-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { tableMoves } from "../table-renames.ts";
import { afterSaleFunctions } from "./orders-after-sale.ts";
import { cartFunctions, shippingRateFunctions } from "./orders-carts.ts";
import { checkoutFunctions } from "./orders-checkout.ts";
import { documentFunctions } from "./orders-documents.ts";
import { orderImportFunctions, orderImportTargets } from "./orders-import.ts";
import {
  KITCHEN_TABLES,
  KITCHEN_TOPIC,
  kitchenContract,
  kitchenOn,
  kitchenSql,
} from "./orders-kitchen.ts";
import { dropShipContract, dropShipFunctions } from "./orders-procurement.ts";
import { columns, paymentWindow } from "./orders-shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { OPERATIONS } from "./permissions-model.ts";

type CommerceKey = keyof CommerceSubjectEventData;

const orderEvent = (
  payload: readonly CommerceKey[],
): { readonly subject: string; readonly payload: readonly CommerceKey[] } => ({
  subject: "orders",
  payload: ["organizationId", "subjectType", "subjectId", "id", ...payload],
});

const EVENTS: BlockSqlEvents<OrdersEvents> = {
  "order.placed": orderEvent([
    "number",
    "customerId",
    "currency",
    "subtotal",
    "discountTotal",
    "shippingTotal",
    "taxTotal",
    "total",
    "units",
  ]),
  "order.paid": orderEvent([
    "number",
    "customerId",
    "currency",
    "total",
    "units",
    "invoiceNumber",
  ]),
  "order.cancelled": orderEvent(["number", "customerId", "reason"]),
  "order.fulfilled": orderEvent(["number", "customerId"]),
  "order.completed": orderEvent(["number", "customerId"]),
  "order.refunded": orderEvent([
    "number",
    "customerId",
    "currency",
    "amount",
    "refundedTotal",
    "status",
  ]),
  "fulfillment.shipped": orderEvent([
    "orderId",
    "number",
    "carrier",
    "trackingNumber",
  ]),
  "fulfillment.delivered": orderEvent(["orderId", "number"]),
  "return.requested": orderEvent(["orderId", "number", "quantity", "reason"]),
  "return.received": orderEvent(["orderId", "number", "quantity"]),
  "order.prepared": orderEvent(["number", "customerId"]),
  "order.served": orderEvent(["number", "customerId"]),
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  migrations: tableMoves("orders", 3),
  entities: {
    order: {
      table: "orders",
      singular: "order",
      primary: true,
      subject: {
        title: "number",
        permissions: { read: "read", write: "manage" },
      },
    },
    cart: { table: "carts", singular: "cart" },
  },
  events: EVENTS,
  hooks: [
    "before_order_place",
    "after_order_place",
    "before_fulfillment_create",
    "after_fulfillment_create",
    "before_refund_create",
    "after_refund_create",
  ],
  options: [
    "paymentWindowMinutes",
    "extraColumns",
    "kitchen",
    "discountMatrix",
  ],
  tables: {
    carts: {
      name: "carts",
      app: {},
      lifecycle: { user: "user", tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        currency: "currency",
        priceList: "price_list_id",
        status: "status",
        email: "email",
        shippingAddress: "shipping_address",
        billingAddress: "billing_address",
        shippingRate: "shipping_rate_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
        convertedAt: "converted_at",
      },
      optional: ["email", "billingAddress"],
      typed: ["status"],
    },
    cartLines: {
      name: "cart_lines",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        cart: "cart_id",
        variant: "variant_id",
        quantity: "quantity",
        unitAmount: "unit_amount",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    shippingRates: {
      name: "order_shipping_rates",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        countries: "countries",
        currency: "currency",
        kind: "kind",
        amount: "amount",
        perKg: "amount_per_kg",
        freeOver: "free_over",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["freeOver"],
      typed: ["kind"],
    },
    orders: {
      name: "orders",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        sequence: "sequence",
        cart: "cart_id",
        customer: "customer_id",
        email: "email",
        status: "status",
        currency: "currency",
        subtotal: "subtotal",
        discountTotal: "discount_total",
        shippingTotal: "shipping_total",
        taxTotal: "tax_total",
        total: "total",
        paidTotal: "paid_total",
        refundedTotal: "refunded_total",
        taxInclusive: "tax_inclusive",
        shippingAddress: "shipping_address",
        billingAddress: "billing_address",
        shipping: "shipping",
        promotions: "promotions",
        tax: "tax",
        taxTransaction: "tax_transaction",
        invoiceNumber: "invoice_number",
        invoiceSequence: "invoice_sequence",
        invoicedAt: "invoiced_at",
        placedAt: "placed_at",
        paidAt: "paid_at",
        fulfilledAt: "fulfilled_at",
        completedAt: "completed_at",
        cancelledAt: "cancelled_at",
        cancelReason: "cancel_reason",
        originType: "origin_type",
        originId: "origin_id",
        buyer: "buyer",
        updatedAt: "updated_at",
      },
      optional: [
        "email",
        "billingAddress",
        "cancelReason",
        "taxTransaction",
        "originType",
        "originId",
        "buyer",
      ],
      typed: ["status"],
    },
    orderLines: {
      name: "order_lines",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        position: "position",
        variant: "variant_id",
        product: "product_id",
        sku: "sku",
        title: "title",
        quantity: "quantity",
        unitAmount: "unit_amount",
        subtotal: "subtotal",
        discount: "discount",
        tax: "tax",
        total: "total",
        requiresShipping: "requires_shipping",
        location: "location_id",
        reservation: "reservation_id",
        fulfilled: "quantity_fulfilled",
        returned: "quantity_returned",
        backordered: "backordered",
        taxCodeId: "tax_code_id",
        unitCost: "unit_cost",
        costSource: "cost_source",
        binId: "bin_id",
        billingParty: "billing_party",
        billingPartyId: "billing_party_id",
        billingAccountId: "billing_account_id",
      },
      optional: [
        "taxCodeId",
        "unitCost",
        "costSource",
        "binId",
        "billingParty",
        "billingPartyId",
        "billingAccountId",
      ],
    },
    payments: {
      name: "order_payments",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        provider: "provider",
        reference: "reference",
        status: "status",
        currency: "currency",
        amount: "amount",
        captured: "captured",
        refunded: "refunded",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      typed: ["status"],
    },
    fulfillments: {
      name: "order_fulfillments",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        location: "location_id",
        status: "status",
        carrier: "carrier",
        trackingNumber: "tracking_number",
        trackingUrl: "tracking_url",
        createdAt: "created_at",
        shippedAt: "shipped_at",
        deliveredAt: "delivered_at",
      },
      optional: ["trackingUrl"],
      typed: ["status"],
    },
    fulfillmentLines: {
      name: "order_fulfillment_lines",
      app: {},
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        fulfillment: "fulfillment_id",
        line: "order_line_id",
        quantity: "quantity",
        detail: "detail",
      },
      optional: ["detail"],
    },
    returns: {
      name: "order_returns",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        status: "status",
        reason: "reason",
        requestedBy: "requested_by",
        createdAt: "created_at",
        receivedAt: "received_at",
      },
      optional: ["reason", "requestedBy"],
      typed: ["status"],
    },
    returnLines: {
      name: "order_return_lines",
      app: {},
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        return: "return_id",
        line: "order_line_id",
        quantity: "quantity",
      },
    },
    refunds: {
      name: "order_refunds",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        payment: "payment_id",
        return: "return_id",
        amount: "amount",
        currency: "currency",
        status: "status",
        reason: "reason",
        providerReference: "provider_reference",
        createdAt: "created_at",
        completedAt: "completed_at",
      },
      optional: ["reason"],
      typed: ["status"],
    },
    ...KITCHEN_TABLES,
  },
};

function tables(ctx: BlockSqlContext, names: OrdersNames): string {
  const catalog = ctx.of("catalog");
  const variant = columns(catalog, "variants");
  const t = (name: string): string => ctx.table(name);

  const tenantRead = (table: string): string =>
    `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`;

  const policy = (table: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: t(table) },
    );

  const ofOrder = (table: string): string => {
    const o = columns(ctx, "orders");

    return `${tenantRead(table)} or exists (select 1 from ${t("orders")} o where o.${o("id")} = ${ctx.col(table, "order")} and o.${o("customer")} = (select auth.uid()))`;
  };

  const c = columns(ctx, "carts");
  const cl = columns(ctx, "cartLines");
  const sr = columns(ctx, "shippingRates");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const p = columns(ctx, "payments");
  const f = columns(ctx, "fulfillments");
  const fl = columns(ctx, "fulfillmentLines");
  const r = columns(ctx, "returns");
  const rl = columns(ctx, "returnLines");
  const rf = columns(ctx, "refunds");

  const currency = (column: string): string =>
    `${column} char(3) not null check (${column} ~ '^[A-Z]{3}$')`;

  const amount = (column: string, nullable = false): string =>
    `${column} bigint ${nullable ? "" : "not null default 0 "}check (${column} >= 0)`;

  const variants = `${catalog.table("variants")} (${variant("id")})`;
  const order = `${t("orders")} (${o("id")}) on delete cascade`;

  // A column definition, left out when the app maps the column to null.
  const optionalColumn = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const priceList =
    catalog.hasTable("priceLists") && catalog.has("prices", "priceList")
      ? ` references ${catalog.table("priceLists")} (${catalog.col("priceLists", "id")}) on delete set null`
      : "";

  return `
create table if not exists ${t("shippingRates")} (
  ${sr("id")} uuid primary key default gen_random_uuid(),
  ${sr("tenant")} ${ctx.idType} not null,
  ${sr("name")} text not null check (length(${sr("name")}) between 1 and 200),
  ${sr("countries")} text[] not null default '{}',
  ${currency(sr("currency"))},
  ${sr("kind")} text not null default 'flat' check (${sr("kind")} in ('flat', 'weight')),
  ${amount(sr("amount"))},
  ${amount(sr("perKg"))},${optionalColumn("shippingRates", "freeOver", (name) => amount(name, true))}
  ${sr("active")} boolean not null default true,
  ${sr("createdAt")} timestamptz not null default now(),
  ${sr("updatedAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${ctx.tableName("shippingRates").name}_tenant_idx`)} on ${t("shippingRates")} (${sr("tenant")}, ${sr("currency")});
${lockModuleTable(ctx, "shippingRates", { read: true })}
${policy("shippingRates", tenantRead("shippingRates"))}

create table if not exists ${t("carts")} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("user")} uuid not null references auth.users (id) on delete cascade,
  ${currency(c("currency"))},
  ${c("priceList")} uuid${priceList},
  ${c("status")} text not null default 'open' check (${c("status")} in ('open', 'converted', 'abandoned')),${optionalColumn("carts", "email", (name) => `${name} text check (length(${name}) <= 320)`)}
  ${c("shippingAddress")} jsonb check (jsonb_typeof(${c("shippingAddress")}) = 'object'),${optionalColumn("carts", "billingAddress", (name) => `${name} jsonb check (jsonb_typeof(${name}) = 'object')`)}
  ${c("shippingRate")} uuid references ${t("shippingRates")} (${sr("id")}) on delete set null,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  ${c("convertedAt")} timestamptz
);
create unique index if not exists ${ctx.naming.rename("carts_open_idx")} on ${t("carts")} (${c("tenant")}, ${c("user")}, ${c("currency")}) where ${ctx.is("carts", "status", c("status"), ["open"])};
create index if not exists ${ctx.naming.rename("carts_user_idx")} on ${t("carts")} (${c("user")});
create index if not exists ${ctx.naming.rename("carts_rate_idx")} on ${t("carts")} (${c("shippingRate")});
${c("priceList") && priceList ? `create index if not exists ${ctx.naming.rename("carts_price_list_idx")} on ${t("carts")} (${c("priceList")});\n` : ""}${lockModuleTable(ctx, "carts", { read: true })}
${policy("carts", `${c("user")} = (select auth.uid()) or ${tenantRead("carts")}`)}

create table if not exists ${t("cartLines")} (
  ${cl("id")} uuid primary key default gen_random_uuid(),
  ${cl("tenant")} ${ctx.idType} not null,
  ${cl("cart")} uuid not null references ${t("carts")} (${c("id")}) on delete cascade,
  ${cl("variant")} uuid not null references ${variants} on delete cascade,
  ${cl("quantity")} integer not null check (${cl("quantity")} between 1 and 10000),
  ${amount(cl("unitAmount"), true)},
  ${cl("createdAt")} timestamptz not null default now(),
  ${cl("updatedAt")} timestamptz not null default now(),
  unique (${cl("cart")}, ${cl("variant")})
);${appUniqueIndex(ctx, "cartLines", ["cart", "variant"])}
create index if not exists ${ctx.naming.rename("cart_lines_variant_idx")} on ${t("cartLines")} (${cl("variant")});
${lockModuleTable(ctx, "cartLines", { read: true })}
${policy("cartLines", `${tenantRead("cartLines")} or exists (select 1 from ${t("carts")} x where x.${c("id")} = ${cl("cart")} and x.${c("user")} = (select auth.uid()))`)}

create table if not exists ${t("orders")} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${ctx.idType} not null,
  ${o("number")} text not null,
  ${o("sequence")} bigint not null,
  ${o("cart")} uuid unique references ${t("carts")} (${c("id")}) on delete set null,
  ${o("customer")} uuid references auth.users (id) on delete set null,${optionalColumn("orders", "email", (name) => `${name} text`)}
  ${o("status")} text not null default 'pending_payment',
  ${currency(o("currency"))},
  ${amount(o("subtotal"))},
  ${amount(o("discountTotal"))},
  ${amount(o("shippingTotal"))},
  ${amount(o("taxTotal"))},
  ${amount(o("total"))},
  ${amount(o("paidTotal"))},
  ${amount(o("refundedTotal"))},
  ${o("taxInclusive")} boolean not null default false,
  ${o("shippingAddress")} jsonb,${optionalColumn("orders", "billingAddress", (name) => `${name} jsonb`)}
  ${o("shipping")} jsonb,
  ${o("promotions")} jsonb not null default '[]',
  ${o("tax")} jsonb,${optionalColumn("orders", "taxTransaction", (name) => `${name} jsonb`)}
  ${o("invoiceNumber")} text,
  ${o("invoiceSequence")} bigint,
  ${o("invoicedAt")} timestamptz,
  ${o("placedAt")} timestamptz not null default now(),
  ${o("paidAt")} timestamptz,
  ${o("fulfilledAt")} timestamptz,
  ${o("completedAt")} timestamptz,
  ${o("cancelledAt")} timestamptz,${optionalColumn("orders", "cancelReason", (name) => `${name} text`)}${optionalColumn("orders", "originType", (name) => `${name} text check (${name} ~ '^[a-z][a-z0-9_]{0,62}$')`)}${optionalColumn("orders", "originId", (name) => `${name} text check (length(${name}) between 1 and 200)`)}${optionalColumn("orders", "buyer", (name) => `${name} jsonb`)}
  ${o("updatedAt")} timestamptz not null default now(),
  unique (${o("tenant")}, ${o("number")}),
  unique (${o("tenant")}, ${o("invoiceNumber")})
);
create index if not exists ${ctx.naming.rename("orders_status_idx")} on ${t("orders")} (${o("tenant")}, ${o("status")}, ${o("placedAt")});
create index if not exists ${ctx.naming.rename("orders_customer_idx")} on ${t("orders")} (${o("customer")});
create index if not exists ${ctx.naming.rename("orders_sequence_idx")} on ${t("orders")} (${o("tenant")}, ${o("sequence")});${
    ctx.has("orders", "originType") && ctx.has("orders", "originId")
      ? `
create unique index if not exists ${ctx.naming.rename("orders_origin_idx")} on ${t("orders")} (${o("tenant")}, ${o("originType")}, ${o("originId")}) where ${o("originId")} is not null and ${ctx.is("orders", "status", o("status"), ["cancelled"], true)};`
      : ""
  }${addExtraColumns(t("orders"), names.extras)}
${lockModuleTable(ctx, "orders", { read: true })}
${policy("orders", `${o("customer")} = (select auth.uid()) or ${tenantRead("orders")}`)}

create table if not exists ${t("orderLines")} (
  ${ol("id")} uuid primary key default gen_random_uuid(),
  ${ol("tenant")} ${ctx.idType} not null,
  ${ol("order")} uuid not null references ${order},
  ${ol("position")} integer not null default 0,
  ${ol("variant")} uuid references ${variants} on delete set null,
  ${ol("product")} uuid,
  ${ol("sku")} text not null,
  ${ol("title")} text not null,
  ${ol("quantity")} integer not null check (${ol("quantity")} > 0),
  ${amount(ol("unitAmount"))},
  ${amount(ol("subtotal"))},
  ${amount(ol("discount"))},
  ${amount(ol("tax"))},
  ${amount(ol("total"))},
  ${ol("requiresShipping")} boolean not null default true,
  ${ol("location")} uuid,
  ${ol("reservation")} uuid,${optionalColumn("orderLines", "taxCodeId", (name) => `${name} uuid`)}${optionalColumn("orderLines", "unitCost", (name) => `${name} bigint check (${name} >= 0)`)}${optionalColumn("orderLines", "costSource", (name) => `${name} text check (${name} in (${COST_SOURCES.map(sqlString).join(", ")}))`)}${optionalColumn("orderLines", "binId", (name) => `${name} uuid`)}${optionalColumn("orderLines", "billingParty", (name) => `${name} text not null default 'customer' check (${name} in (${BILLING_PARTIES.map(sqlString).join(", ")}))`)}${optionalColumn("orderLines", "billingPartyId", (name) => `${name} text`)}${optionalColumn("orderLines", "billingAccountId", (name) => `${name} uuid`)}
  ${ol("fulfilled")} integer not null default 0 check (${ol("fulfilled")} between 0 and ${ol("quantity")}),
  ${ol("returned")} integer not null default 0 check (${ol("returned")} between 0 and ${ol("quantity")}),
  ${ol("backordered")} boolean not null default false
);
create index if not exists ${ctx.naming.rename("order_lines_order_idx")} on ${t("orderLines")} (${ol("order")});
create index if not exists ${ctx.naming.rename("order_lines_variant_idx")} on ${t("orderLines")} (${ol("variant")});
${lockModuleTable(ctx, "orderLines", { read: true })}
${policy("orderLines", ofOrder("orderLines"))}

create table if not exists ${t("payments")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("order")} uuid not null references ${order},
  ${p("provider")} text not null,
  ${p("reference")} text not null,
  ${p("status")} text not null check (${p("status")} in ('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled')),
  ${currency(p("currency"))},
  ${amount(p("amount"))},
  ${amount(p("captured"))},
  ${amount(p("refunded"))},
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("provider")}, ${p("reference")})
);${appUniqueIndex(ctx, "payments", ["provider", "reference"])}
create index if not exists ${ctx.naming.rename("order_payments_order_idx")} on ${t("payments")} (${p("order")});
${lockModuleTable(ctx, "payments", { read: true })}
${policy("payments", ofOrder("payments"))}

create table if not exists ${t("fulfillments")} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("order")} uuid not null references ${order},
  ${f("location")} uuid,
  ${f("status")} text not null default 'pending' check (${f("status")} in ('pending', 'shipped', 'delivered', 'cancelled')),
  ${f("carrier")} text,
  ${f("trackingNumber")} text,${optionalColumn("fulfillments", "trackingUrl", (name) => `${name} text check (${name} ~ '^https://')`)}
  ${f("createdAt")} timestamptz not null default now(),
  ${f("shippedAt")} timestamptz,
  ${f("deliveredAt")} timestamptz
);
create index if not exists ${sqlIdent(`${ctx.tableName("fulfillments").name}_${ctx.naming.rename("order_idx")}`)} on ${t("fulfillments")} (${f("order")});
${lockModuleTable(ctx, "fulfillments", { read: true })}
${policy("fulfillments", ofOrder("fulfillments"))}

create table if not exists ${t("fulfillmentLines")} (
  ${fl("tenant")} ${ctx.idType} not null,
  ${fl("fulfillment")} uuid not null references ${t("fulfillments")} (${f("id")}) on delete cascade,
  ${fl("line")} uuid not null references ${t("orderLines")} (${ol("id")}) on delete cascade,
  ${fl("quantity")} integer not null check (${fl("quantity")} > 0),${optionalColumn("fulfillmentLines", "detail", (name) => `${name} jsonb check (${name} is null or jsonb_typeof(${name}) = 'object')`)}
  primary key (${fl("fulfillment")}, ${fl("line")})
);${appUniqueIndex(ctx, "fulfillmentLines", ["fulfillment", "line"])}
create index if not exists ${sqlIdent(`${ctx.tableName("fulfillmentLines").name}_${ctx.naming.rename("line_idx")}`)} on ${t("fulfillmentLines")} (${fl("line")});
${lockModuleTable(ctx, "fulfillmentLines", { read: true })}
${policy("fulfillmentLines", tenantRead("fulfillmentLines"))}

create table if not exists ${t("returns")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("order")} uuid not null references ${order},
  ${r("status")} text not null default 'requested' check (${r("status")} in ('requested', 'received', 'rejected')),${optionalColumn("returns", "reason", (name) => `${name} text check (length(${name}) <= 2000)`)}${optionalColumn("returns", "requestedBy", (name) => `${name} uuid default auth.uid()`)}
  ${r("createdAt")} timestamptz not null default now(),
  ${r("receivedAt")} timestamptz
);
create index if not exists ${ctx.naming.rename("order_returns_order_idx")} on ${t("returns")} (${r("order")});
${lockModuleTable(ctx, "returns", { read: true })}
${policy("returns", ofOrder("returns"))}

create table if not exists ${t("returnLines")} (
  ${rl("tenant")} ${ctx.idType} not null,
  ${rl("return")} uuid not null references ${t("returns")} (${r("id")}) on delete cascade,
  ${rl("line")} uuid not null references ${t("orderLines")} (${ol("id")}) on delete cascade,
  ${rl("quantity")} integer not null check (${rl("quantity")} > 0),
  primary key (${rl("return")}, ${rl("line")})
);${appUniqueIndex(ctx, "returnLines", ["return", "line"])}
create index if not exists ${ctx.naming.rename("order_return_lines_line_idx")} on ${t("returnLines")} (${rl("line")});
${lockModuleTable(ctx, "returnLines", { read: true })}
${policy("returnLines", tenantRead("returnLines"))}

create table if not exists ${t("refunds")} (
  ${rf("id")} uuid primary key default gen_random_uuid(),
  ${rf("tenant")} ${ctx.idType} not null,
  ${rf("order")} uuid not null references ${order},
  ${rf("payment")} uuid not null references ${t("payments")} (${p("id")}) on delete cascade,
  ${rf("return")} uuid references ${t("returns")} (${r("id")}) on delete set null,
  ${rf("amount")} bigint not null check (${rf("amount")} > 0),
  ${currency(rf("currency"))},
  ${rf("status")} text not null default 'pending' check (${rf("status")} in ('pending', 'succeeded', 'failed')),${optionalColumn("refunds", "reason", (name) => `${name} text check (length(${name}) <= 2000)`)}
  ${rf("providerReference")} text,
  ${rf("createdAt")} timestamptz not null default now(),
  ${rf("completedAt")} timestamptz
);
create index if not exists ${ctx.naming.rename("order_refunds_order_idx")} on ${t("refunds")} (${rf("order")});
create index if not exists ${ctx.naming.rename("order_refunds_payment_idx")} on ${t("refunds")} (${rf("payment")});
create index if not exists ${ctx.naming.rename("order_refunds_return_idx")} on ${t("refunds")} (${rf("return")});
create unique index if not exists ${ctx.naming.rename("order_refunds_provider_reference_idx")} on ${t("refunds")} (${rf("providerReference")}) where ${rf("providerReference")} is not null;
${lockModuleTable(ctx, "refunds", { read: true })}
${policy("refunds", ofOrder("refunds"))}
`;
}

/** `options.extraColumns`, added to the orders table. */
const extrasOf = (ctx: BlockSqlContext) =>
  ctx.extraColumns("orders", ["fields"]);

function namesOf(ctx: BlockSqlContext): OrdersNames {
  return {
    extras: extrasOf(ctx),
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", OPERATIONS["orders.manage"]),
    read: ctx.permission("read", OPERATIONS["orders.read"]),
    prepare: ctx.permission("prepare", OPERATIONS["orders.prepare"]),
  };
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  paymentWindow(ctx);
  const names = namesOf(ctx);

  return `${schemaPreamble(ctx)}
-- Carts on any signed-in user (anonymous sign-ins included), checkout into
-- orders with numbers, payments, fulfillments, returns and refunds.
${tables(ctx, names)}${shippingRateFunctions(ctx, names)}${cartFunctions(ctx, names)}${checkoutFunctions(ctx, names)}${documentFunctions(ctx, names)}${dropShipFunctions(ctx, names)}${afterSaleFunctions(ctx, names)}${orderImportFunctions(ctx, names)}${kitchenOn(ctx) ? kitchenSql(ctx, names) : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_shipping_rate",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_shipping_rate", args: ["uuid"], returns: "boolean" },
    {
      name: "create_cart",
      args: ["{id}", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "add_to_cart",
      args: ["uuid", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "set_cart_line",
      args: ["uuid", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "set_cart_details",
      args: ["uuid", "text", "jsonb", "jsonb"],
      returns: "boolean",
    },
    {
      name: "set_cart_shipping_rate",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    { name: "shipping_options", args: ["uuid"], returns: "jsonb" },
    { name: "price_cart", args: ["uuid"], returns: "jsonb" },
    { name: "merge_carts", args: ["uuid", "uuid"], returns: "integer" },
    {
      name: "place_order",
      args: [
        "uuid",
        "jsonb",
        "bigint",
        "uuid",
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "record_payment",
      args: [
        "uuid",
        "text",
        "text",
        "text",
        "text",
        "bigint",
        "bigint",
        "bigint",
      ],
      returns: "jsonb",
    },
    {
      name: "set_order_tax_transaction",
      args: ["uuid", "jsonb"],
      returns: "boolean",
    },
    {
      name: "order_from_lines",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    ...(ctx.installed("quotes")
      ? [
          {
            name: "order_from_quote",
            args: ["uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    { name: "cancel_order", args: ["uuid", "text"], returns: "boolean" },
    { name: "expire_orders", args: ["integer"], returns: "integer" },
    { name: "get_order", args: ["uuid"], returns: "jsonb" },
    {
      name: "create_fulfillment",
      args: ["uuid", "jsonb", "uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "ship_fulfillment",
      args: ["uuid", "text", "text", "text"],
      returns: "boolean",
    },
    { name: "deliver_fulfillment", args: ["uuid"], returns: "boolean" },
    { name: "cancel_fulfillment", args: ["uuid"], returns: "boolean" },
    {
      name: "request_return",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "receive_return",
      args: ["uuid", "boolean", "uuid"],
      returns: "boolean",
    },
    { name: "reject_return", args: ["uuid"], returns: "boolean" },
    {
      name: "create_refund",
      args: ["uuid", "bigint", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "complete_refund",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    ...(kitchenOn(ctx) ? kitchenContract() : []),
    ...dropShipContract(ctx),
  ];
}

export const ORDERS: BlockSqlDefinition = {
  name: "orders",
  scopes: ["tenant"],
  title: "Orders",
  description:
    "Carts on anonymous or signed-in users, checkout priced from the catalog, confirmed orders from lines or an accepted quote with stock allocations, gapless order and invoice numbers, payments, fulfillments, returns and refunds, with an optional kitchen display. With invoices, a paid order gets an issued, paid invoice.",
  requires: ["memberships", "permissions", "catalog"],
  integrates: [
    "outbox",
    "inventory",
    "promotions",
    "numbering",
    "legal-entities",
    "state-machine",
    "invoices",
    "quotes",
    "contacts",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
  upgrades: [
    {
      from: 1,
      description:
        "With invoices, record_payment creates an issued, paid invoice for a newly paid order and stores its identifier as the order's invoice number.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "Orders made from lines or an accepted quote start confirmed and hold their stock through inventory allocations with backorders; orders gain origin columns and fulfillment lines a detail column for lots and serial numbers.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
  contributes: { imports: orderImportTargets },
  topics: (ctx) =>
    kitchenOn(ctx) ? [`${KITCHEN_TOPIC}:{organizationId}`] : [],
};
