import "server-only";
import type {
  Order,
  OrderStatus,
  PricedCart,
} from "better-supabase/blocks/orders";
import type { Money } from "better-supabase/commerce";

import { PRODUCT_STATUSES } from "better-supabase/blocks/catalog";
import { ORDER_STATUSES } from "better-supabase/blocks/orders";
import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { SHOP_CURRENCY } from "./shop-currency";
import { shopOrders } from "./shop-server";

/** What a loader gives a component: the data, a failed read, or no organization. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

const Id = v.pipe(v.string(), v.uuid());
const MinorUnits = v.pipe(v.string(), v.regex(/^-?\d+$/));

const toMoney = (amount: string, currency: string): Money =>
  money(BigInt(amount), currency);

/**
 * Runs a loader and turns a thrown read into `{ kind: "error" }`, so the
 * component shows Retry. A failed read is never cached.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

const ProductRow = v.object({
  id: Id,
  title: v.string(),
  description: v.nullable(v.string()),
  status: v.picklist(PRODUCT_STATUSES),
  variantId: Id,
  sku: v.string(),
  amount: v.nullable(MinorUnits),
  available: v.nullable(v.number()),
});

export interface Product {
  readonly id: string;
  readonly title: string;
  readonly description: string | null;
  readonly status: (typeof PRODUCT_STATUSES)[number];
  readonly variantId: string;
  readonly sku: string;
  readonly price: Money | null;
  readonly available: number | null;
}

/**
 * The organization's products with their first variant and its base price. The
 * catalog block has no list function, so `api.shop_products` reads them with
 * the caller's token and the block's `catalog.read` policy.
 */
async function loadProducts(): Promise<readonly Product[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const rows = v.parse(
    v.array(ProductRow),
    await db.$api("shop_products", { tenant, currency: SHOP_CURRENCY }),
  );

  return rows.map(({ amount, ...row }) => ({
    ...row,
    price: amount === null ? null : toMoney(amount, SHOP_CURRENCY),
  }));
}

export function getProducts(): Promise<Loaded<readonly Product[]>> {
  return settle(loadProducts);
}

const StockLevels = v.object({
  locations: v.array(
    v.object({
      id: Id,
      code: v.string(),
      name: v.string(),
      active: v.boolean(),
    }),
  ),
  levels: v.array(
    v.object({
      variantId: Id,
      productTitle: v.string(),
      sku: v.string(),
      locationId: Id,
      onHand: v.number(),
      reserved: v.number(),
      available: v.number(),
      reorderPoint: v.nullable(v.number()),
    }),
  ),
});

export type StockLevels = v.InferOutput<typeof StockLevels>;

/**
 * Every tracked variant at every active location, zero where nothing was
 * counted.
 */
async function loadStockLevels(): Promise<StockLevels | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  return v.parse(StockLevels, await db.$api("shop_stock_levels", { tenant }));
}

export function getStockLevels(): Promise<Loaded<StockLevels>> {
  return settle(loadStockLevels);
}

const OrderList = v.object({
  orders: v.array(
    v.object({
      id: Id,
      number: v.string(),
      status: v.picklist(ORDER_STATUSES),
      currency: v.string(),
      total: MinorUnits,
      placedAt: v.string(),
      lines: v.number(),
    }),
  ),
  drafts: v.array(
    v.object({
      id: Id,
      currency: v.string(),
      createdAt: v.string(),
      lines: v.number(),
    }),
  ),
});

export interface OrderSummary {
  readonly id: string;
  readonly number: string;
  readonly status: OrderStatus;
  readonly total: Money;
  readonly placedAt: string;
  readonly lines: number;
}

export interface DraftSummary {
  readonly id: string;
  readonly currency: string;
  readonly createdAt: string;
  readonly lines: number;
}

export interface Orders {
  readonly orders: readonly OrderSummary[];
  readonly drafts: readonly DraftSummary[];
}

/** The organization's placed orders and the caller's open carts (draft orders). */
async function loadOrders(): Promise<Orders | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const list = v.parse(OrderList, await db.$api("shop_orders", { tenant }));

  return {
    drafts: list.drafts,
    orders: list.orders.map(({ total, currency, ...order }) => ({
      ...order,
      total: toMoney(total, currency),
    })),
  };
}

export function getOrders(): Promise<Loaded<Orders>> {
  return settle(loadOrders);
}

export interface DetailLine {
  readonly id: string;
  readonly sku: string;
  readonly title: string;
  readonly quantity: number;
  readonly unitAmount: Money;
  readonly discount: Money;
  readonly total: Money;
}

export interface DetailPromotion {
  readonly code: string | null;
  readonly name: string;
  readonly discount: Money;
}

interface DetailTotals {
  readonly id: string;
  readonly currency: string;
  readonly lines: readonly DetailLine[];
  readonly promotions: readonly DetailPromotion[];
  readonly subtotal: Money;
  readonly discountTotal: Money;
  readonly shippingTotal: Money;
  readonly total: Money;
}

/** A placed order, with plain values so the private cache can keep it. */
export interface OrderView extends DetailTotals {
  readonly kind: "order";
  readonly number: string;
  readonly status: OrderStatus;
  readonly taxTotal: Money;
  readonly paidTotal: Money;
  readonly placedAt: string;
  readonly fulfillments: readonly {
    readonly id: string;
    readonly status: Order["fulfillments"][number]["status"];
  }[];
}

/** The caller's open cart, shown as a draft order. */
export interface DraftView extends DetailTotals {
  readonly kind: "draft";
  readonly problems: readonly string[];
}

const promotionsOf = (
  promotions: Order["promotions"],
): readonly DetailPromotion[] =>
  promotions.map((promotion) => ({
    code: promotion.code ?? null,
    name: promotion.name,
    discount: promotion.discount,
  }));

const linesOf = (lines: PricedCart["lines"] | Order["lines"]) =>
  lines.map((line) => ({
    id: line.id,
    sku: line.sku,
    title: line.title,
    quantity: line.quantity,
    unitAmount: line.unitAmount,
    discount: line.discount,
    total: line.total,
  }));

function orderView(order: Order): OrderView {
  return {
    kind: "order",
    id: order.id,
    number: order.number,
    status: order.status,
    currency: order.currency,
    lines: linesOf(order.lines),
    promotions: promotionsOf(order.promotions),
    subtotal: order.subtotal,
    discountTotal: order.discountTotal,
    shippingTotal: order.shippingTotal,
    taxTotal: order.taxTotal,
    total: order.total,
    paidTotal: order.paidTotal,
    placedAt: order.placedAt.toString(),
    fulfillments: order.fulfillments.map(({ id, status }) => ({ id, status })),
  };
}

function draftView(cart: PricedCart): DraftView {
  return {
    kind: "draft",
    id: cart.id,
    currency: cart.currency,
    lines: linesOf(cart.lines),
    promotions: promotionsOf(cart.promotions),
    subtotal: cart.subtotal,
    discountTotal: cart.discountTotal,
    shippingTotal: cart.shippingTotal,
    total: cart.total,
    problems: cart.problems.map((problem) => problem.problem),
  };
}

/**
 * An order by id, or the caller's open cart with that id as a draft. Resolves
 * to null when neither exists or the caller can't read it.
 */
async function loadOrderDetail(
  id: string,
): Promise<OrderView | DraftView | null> {
  "use cache: private";
  const { supabase } = await bsb.cached();
  const orders = shopOrders(supabase);

  const order = await orders.getOrder(id);

  if (order.ok) {
    return orderView(order.data);
  }

  if (order.error.kind !== "not_found") {
    throw new Error(order.error.message);
  }

  const cart = await orders.priceCart(id);

  if (cart.ok) {
    return cart.data.status === "open" ? draftView(cart.data) : null;
  }

  if (cart.error.kind !== "not_found") {
    throw new Error(cart.error.message);
  }

  return null;
}

export type OrderDetail =
  | { readonly kind: "ok"; readonly data: OrderView | DraftView }
  | { readonly kind: "error" }
  | { readonly kind: "not-found" };

export async function getOrderDetail(id: string): Promise<OrderDetail> {
  if (!v.is(Id, id)) {
    return { kind: "not-found" };
  }

  try {
    const data = await loadOrderDetail(id);

    return data === null ? { kind: "not-found" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
