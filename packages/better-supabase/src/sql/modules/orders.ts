import type { OrdersEvents } from "../../blocks/orders/events.ts";
import type { CommerceSubjectEventData } from "../../core/block-events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";
import type { OrdersNames } from "./orders-shared.ts";

import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { afterSaleFunctions } from "./orders-after-sale.ts";
import { cartFunctions, shippingRateFunctions } from "./orders-carts.ts";
import { checkoutFunctions } from "./orders-checkout.ts";
import {
  KITCHEN_TABLES,
  KITCHEN_TOPIC,
  kitchenContract,
  kitchenOn,
  kitchenSql,
} from "./orders-kitchen.ts";
import { columns, paymentWindow } from "./orders-shared.ts";

type CommerceKey = keyof CommerceSubjectEventData;

const orderEvent = (
  payload: readonly CommerceKey[],
): { readonly subject: string; readonly payload: readonly CommerceKey[] } => ({
  subject: "orders",
  payload: ["organizationId", "subjectType", "subjectId", "id", ...payload],
});

const EVENTS: ModuleEvents<OrdersEvents> = {
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

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_order_place",
    "after_order_place",
    "before_fulfillment_create",
    "after_fulfillment_create",
    "before_refund_create",
    "after_refund_create",
  ],
  options: ["paymentWindowMinutes", "extraColumns", "kitchen"],
  tables: {
    carts: {
      name: "carts",
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
    },
    cartLines: {
      name: "cart_lines",
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
      name: "shipping_rates",
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
    },
    orders: {
      name: "orders",
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
        updatedAt: "updated_at",
      },
    },
    orderLines: {
      name: "order_lines",
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
      },
    },
    payments: {
      name: "order_payments",
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
    },
    fulfillments: {
      name: "fulfillments",
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
    },
    fulfillmentLines: {
      name: "fulfillment_lines",
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        fulfillment: "fulfillment_id",
        line: "order_line_id",
        quantity: "quantity",
      },
    },
    returns: {
      name: "order_returns",
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
    },
    returnLines: {
      name: "order_return_lines",
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
    },
    ...KITCHEN_TABLES,
  },
};

function tables(ctx: ModuleContext, names: OrdersNames): string {
  const catalog = ctx.of("catalog");
  const variant = columns(catalog, "variants");
  const t = (name: string): string => ctx.table(name);

  const tenantRead = (table: string): string =>
    `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`;

  const policy = (
    table: string,
    using: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${using});`;

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
  ${amount(sr("perKg"))},
  ${amount(sr("freeOver"), true)},
  ${sr("active")} boolean not null default true,
  ${sr("createdAt")} timestamptz not null default now(),
  ${sr("updatedAt")} timestamptz not null default now()
);
create index if not exists shipping_rates_tenant_idx on ${t("shippingRates")} (${sr("tenant")}, ${sr("currency")});
${lockTable(t("shippingRates"), { read: true })}
${policy("shippingRates", tenantRead("shippingRates"))}

create table if not exists ${t("carts")} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("user")} uuid not null references auth.users (id) on delete cascade,
  ${currency(c("currency"))},
  ${c("priceList")} uuid${priceList},
  ${c("status")} text not null default 'open' check (${c("status")} in ('open', 'converted', 'abandoned')),
  ${c("email")} text check (length(${c("email")}) <= 320),
  ${c("shippingAddress")} jsonb check (jsonb_typeof(${c("shippingAddress")}) = 'object'),
  ${c("billingAddress")} jsonb check (jsonb_typeof(${c("billingAddress")}) = 'object'),
  ${c("shippingRate")} uuid references ${t("shippingRates")} (${sr("id")}) on delete set null,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  ${c("convertedAt")} timestamptz
);
create unique index if not exists carts_open_idx on ${t("carts")} (${c("tenant")}, ${c("user")}, ${c("currency")}) where ${c("status")} = 'open';
create index if not exists carts_user_idx on ${t("carts")} (${c("user")});
create index if not exists carts_rate_idx on ${t("carts")} (${c("shippingRate")});
${c("priceList") && priceList ? `create index if not exists carts_price_list_idx on ${t("carts")} (${c("priceList")});\n` : ""}${lockTable(t("carts"), { read: true })}
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
);
create index if not exists cart_lines_variant_idx on ${t("cartLines")} (${cl("variant")});
${lockTable(t("cartLines"), { read: true })}
${policy("cartLines", `${tenantRead("cartLines")} or exists (select 1 from ${t("carts")} x where x.${c("id")} = ${cl("cart")} and x.${c("user")} = (select auth.uid()))`)}

create table if not exists ${t("orders")} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${ctx.idType} not null,
  ${o("number")} text not null,
  ${o("sequence")} bigint not null,
  ${o("cart")} uuid unique references ${t("carts")} (${c("id")}) on delete set null,
  ${o("customer")} uuid references auth.users (id) on delete set null,
  ${o("email")} text,
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
  ${o("shippingAddress")} jsonb,
  ${o("billingAddress")} jsonb,
  ${o("shipping")} jsonb,
  ${o("promotions")} jsonb not null default '[]',
  ${o("tax")} jsonb,
  ${o("taxTransaction")} jsonb,
  ${o("invoiceNumber")} text,
  ${o("invoiceSequence")} bigint,
  ${o("invoicedAt")} timestamptz,
  ${o("placedAt")} timestamptz not null default now(),
  ${o("paidAt")} timestamptz,
  ${o("fulfilledAt")} timestamptz,
  ${o("completedAt")} timestamptz,
  ${o("cancelledAt")} timestamptz,
  ${o("cancelReason")} text,
  ${o("updatedAt")} timestamptz not null default now(),
  unique (${o("tenant")}, ${o("number")}),
  unique (${o("tenant")}, ${o("invoiceNumber")})
);
create index if not exists orders_status_idx on ${t("orders")} (${o("tenant")}, ${o("status")}, ${o("placedAt")});
create index if not exists orders_customer_idx on ${t("orders")} (${o("customer")});
create index if not exists orders_sequence_idx on ${t("orders")} (${o("tenant")}, ${o("sequence")});${addExtraColumns(t("orders"), names.extras)}
${lockTable(t("orders"), { read: true })}
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
  ${ol("reservation")} uuid,
  ${ol("fulfilled")} integer not null default 0 check (${ol("fulfilled")} between 0 and ${ol("quantity")}),
  ${ol("returned")} integer not null default 0 check (${ol("returned")} between 0 and ${ol("quantity")}),
  ${ol("backordered")} boolean not null default false
);
create index if not exists order_lines_order_idx on ${t("orderLines")} (${ol("order")});
create index if not exists order_lines_variant_idx on ${t("orderLines")} (${ol("variant")});
${lockTable(t("orderLines"), { read: true })}
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
);
create index if not exists order_payments_order_idx on ${t("payments")} (${p("order")});
${lockTable(t("payments"), { read: true })}
${policy("payments", ofOrder("payments"))}

create table if not exists ${t("fulfillments")} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("order")} uuid not null references ${order},
  ${f("location")} uuid,
  ${f("status")} text not null default 'pending' check (${f("status")} in ('pending', 'shipped', 'delivered', 'cancelled')),
  ${f("carrier")} text,
  ${f("trackingNumber")} text,
  ${f("trackingUrl")} text check (${f("trackingUrl")} ~ '^https://'),
  ${f("createdAt")} timestamptz not null default now(),
  ${f("shippedAt")} timestamptz,
  ${f("deliveredAt")} timestamptz
);
create index if not exists fulfillments_order_idx on ${t("fulfillments")} (${f("order")});
${lockTable(t("fulfillments"), { read: true })}
${policy("fulfillments", ofOrder("fulfillments"))}

create table if not exists ${t("fulfillmentLines")} (
  ${fl("tenant")} ${ctx.idType} not null,
  ${fl("fulfillment")} uuid not null references ${t("fulfillments")} (${f("id")}) on delete cascade,
  ${fl("line")} uuid not null references ${t("orderLines")} (${ol("id")}) on delete cascade,
  ${fl("quantity")} integer not null check (${fl("quantity")} > 0),
  primary key (${fl("fulfillment")}, ${fl("line")})
);
create index if not exists fulfillment_lines_line_idx on ${t("fulfillmentLines")} (${fl("line")});
${lockTable(t("fulfillmentLines"), { read: true })}
${policy("fulfillmentLines", tenantRead("fulfillmentLines"))}

create table if not exists ${t("returns")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("order")} uuid not null references ${order},
  ${r("status")} text not null default 'requested' check (${r("status")} in ('requested', 'received', 'rejected')),
  ${r("reason")} text check (length(${r("reason")}) <= 2000),
  ${r("requestedBy")} uuid default auth.uid(),
  ${r("createdAt")} timestamptz not null default now(),
  ${r("receivedAt")} timestamptz
);
create index if not exists order_returns_order_idx on ${t("returns")} (${r("order")});
${lockTable(t("returns"), { read: true })}
${policy("returns", ofOrder("returns"))}

create table if not exists ${t("returnLines")} (
  ${rl("tenant")} ${ctx.idType} not null,
  ${rl("return")} uuid not null references ${t("returns")} (${r("id")}) on delete cascade,
  ${rl("line")} uuid not null references ${t("orderLines")} (${ol("id")}) on delete cascade,
  ${rl("quantity")} integer not null check (${rl("quantity")} > 0),
  primary key (${rl("return")}, ${rl("line")})
);
create index if not exists order_return_lines_line_idx on ${t("returnLines")} (${rl("line")});
${lockTable(t("returnLines"), { read: true })}
${policy("returnLines", tenantRead("returnLines"))}

create table if not exists ${t("refunds")} (
  ${rf("id")} uuid primary key default gen_random_uuid(),
  ${rf("tenant")} ${ctx.idType} not null,
  ${rf("order")} uuid not null references ${order},
  ${rf("payment")} uuid not null references ${t("payments")} (${p("id")}) on delete cascade,
  ${rf("return")} uuid references ${t("returns")} (${r("id")}) on delete set null,
  ${rf("amount")} bigint not null check (${rf("amount")} > 0),
  ${currency(rf("currency"))},
  ${rf("status")} text not null default 'pending' check (${rf("status")} in ('pending', 'succeeded', 'failed')),
  ${rf("reason")} text check (length(${rf("reason")}) <= 2000),
  ${rf("providerReference")} text,
  ${rf("createdAt")} timestamptz not null default now(),
  ${rf("completedAt")} timestamptz
);
create index if not exists order_refunds_order_idx on ${t("refunds")} (${rf("order")});
create index if not exists order_refunds_payment_idx on ${t("refunds")} (${rf("payment")});
create index if not exists order_refunds_return_idx on ${t("refunds")} (${rf("return")});
create unique index if not exists order_refunds_provider_reference_idx on ${t("refunds")} (${rf("providerReference")}) where ${rf("providerReference")} is not null;
${lockTable(t("refunds"), { read: true })}
${policy("refunds", ofOrder("refunds"))}
`;
}

/** `options.extraColumns`, added to the orders table. */
const extrasOf = (ctx: ModuleContext) => ctx.extraColumns("orders", ["fields"]);

function namesOf(ctx: ModuleContext): OrdersNames {
  return {
    extras: extrasOf(ctx),
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", OPERATIONS["orders.manage"]),
    read: ctx.permission("read", OPERATIONS["orders.read"]),
    prepare: ctx.permission("prepare", OPERATIONS["orders.prepare"]),
  };
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  paymentWindow(ctx);
  const names = namesOf(ctx);

  return `${schemaPreamble(ctx)}
-- Carts on any signed-in user (anonymous sign-ins included), checkout into
-- orders with numbers, payments, fulfillments, returns and refunds.
${tables(ctx, names)}${shippingRateFunctions(ctx, names)}${cartFunctions(ctx, names)}${checkoutFunctions(ctx, names)}${afterSaleFunctions(ctx, names)}${kitchenOn(ctx) ? kitchenSql(ctx, names) : ""}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
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
  ];
}

export const ORDERS: ModuleDefinition = {
  name: "orders",
  scopes: ["tenant"],
  title: "Orders",
  description:
    "Carts on anonymous or signed-in users, checkout priced from the catalog, gapless order and invoice numbers, payments, fulfillments, returns and refunds, with an optional kitchen display.",
  requires: ["tenant", "access", "catalog"],
  integrates: [
    "outbox",
    "inventory",
    "promotions",
    "number-sequences",
    "state-machine",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  topics: (ctx) =>
    kitchenOn(ctx) ? [`${KITCHEN_TOPIC}:{organizationId}`] : [],
};
