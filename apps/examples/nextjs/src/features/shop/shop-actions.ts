"use server";

import { dbError, err, ok } from "better-supabase";
import { ADJUST_REASONS } from "better-supabase/blocks/inventory";
import { money, parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { SHOP_CURRENCY } from "./shop-currency";
import { shopOrders } from "./shop-server";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

const Decimal = v.pipe(
  v.string(),
  v.trim(),
  v.regex(/^\d+(\.\d{1,2})?$/, "Enter an amount such as 49.00"),
);

const Count = v.pipe(
  v.union([v.number(), v.pipe(v.string(), v.trim(), v.toNumber())]),
  v.integer(),
);

/**
 * Creates an active product with one variant and its base price, so the
 * grid has something to show and a draft order something to add.
 */
export const createProduct = bs.action(
  {
    input: v.object({
      title: Text(200),
      sku: v.pipe(Text(64), v.toUpperCase()),
      price: Decimal,
    }),
    requireTenant: true,
    authorize: (session) => can(session, "catalog.manage"),
  },
  async ({ title, sku, price }, { tenant, supabase, auth }) => {
    const { catalog } = blocks(supabase);
    const product = await catalog.createProduct(tenant, { title });

    if (!product.ok) {
      return product;
    }

    const variant = await catalog.createVariant(product.data.id, { sku });

    if (!variant.ok) {
      return variant;
    }

    const priced = await catalog.setPrice(variant.data.id, {
      amount: parseMoney(price, SHOP_CURRENCY),
    });

    if (!priced.ok) {
      return priced;
    }

    const activated = await catalog.setProductStatus(product.data.id, "active");

    if (!activated.ok) {
      return activated;
    }

    refreshCaller(auth);

    return ok(product.data.id);
  },
);

/** The first stock location, so counts have somewhere to go. */
export const createMainLocation = bs.action(
  {
    input: v.object({}),
    requireTenant: true,
    authorize: (session) => can(session, "inventory.manage"),
  },
  async (_input, { tenant, supabase, auth }) => {
    const saved = await blocks(supabase).inventory.saveLocation(tenant, {
      code: "MAIN",
      name: "Main warehouse",
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(saved.data.id);
  },
);

/** Adds or removes units at a location; a negative quantity removes them. */
export const adjustStock = bs.action(
  {
    input: v.object({
      variantId: Id,
      locationId: Id,
      quantity: v.pipe(
        Count,
        v.check((quantity) => quantity !== 0, "Enter a quantity other than 0"),
      ),
      reason: v.picklist(ADJUST_REASONS),
      note: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "inventory.manage"),
  },
  async (
    { variantId, locationId, quantity, reason, note },
    { supabase, auth },
  ) => {
    const adjusted = await blocks(supabase).inventory.adjustStock(
      variantId,
      locationId,
      quantity,
      reason,
      note === "" ? undefined : note,
    );

    if (!adjusted.ok) {
      return adjusted;
    }

    refreshCaller(auth);

    return ok(adjusted.data.onHand);
  },
);

/**
 * Adds a product to the caller's open cart, which the shop shows as the
 * draft order. `createCart` returns the open cart when there is one.
 */
export const createDraftOrder = bs.action(
  {
    input: v.object({
      variantId: Id,
      quantity: v.pipe(Count, v.minValue(1), v.maxValue(999)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ variantId, quantity }, { tenant, supabase, auth }) => {
    const orders = shopOrders(supabase);
    const cart = await orders.createCart(tenant, { currency: SHOP_CURRENCY });

    if (!cart.ok) {
      return cart;
    }

    const added = await orders.addToCart(cart.data.id, variantId, quantity);

    if (!added.ok) {
      return added;
    }

    refreshCaller(auth);

    return ok(cart.data.id);
  },
);

/** Places the draft: prices the cart, reserves its stock and creates the order. */
export const placeOrder = bs.action(
  {
    input: v.object({ cartId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ cartId }, { supabase, auth }) => {
    const checkout = await shopOrders(supabase).checkout(cartId);

    if (!checkout.ok) {
      return checkout;
    }

    refreshCaller(auth);

    return ok(checkout.data.order.id);
  },
);

/**
 * Records a manual payment for the order's full total. The example has no
 * payments provider; a real shop records payments from its webhook.
 */
export const markOrderPaid = bs.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ orderId }, { supabase, auth }) => {
    const orders = shopOrders(supabase);
    // Read as the caller first: the payment itself goes through the service role.
    const order = await orders.getOrder(orderId);

    if (!order.ok) {
      return order;
    }

    if (order.data.status !== "pending_payment") {
      return err(
        dbError("invalid_request", "Only an unpaid order can be paid"),
      );
    }

    const due = money(
      order.data.total.amount - order.data.paidTotal.amount,
      order.data.currency,
    );

    const recorded = await orders.recordPayment(orderId, {
      id: `manual:${crypto.randomUUID()}`,
      provider: "manual",
      status: "succeeded",
      amount: due,
      captured: due,
      refunded: money(0n, order.data.currency),
      reference: orderId,
      metadata: {},
    });

    if (!recorded.ok) {
      return recorded;
    }

    refreshCaller(auth);

    return ok(recorded.data.status);
  },
);

/** Cancels an unpaid order and releases its stock. */
export const cancelOrder = bs.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ orderId }, { supabase, auth }) => {
    const cancelled = await shopOrders(supabase).cancelOrder(
      orderId,
      "Cancelled from the shop",
    );

    if (!cancelled.ok) {
      return cancelled;
    }

    refreshCaller(auth);

    return ok(cancelled.data);
  },
);

/** Creates a fulfillment for every unit not fulfilled yet. */
export const fulfillOrder = bs.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ orderId }, { supabase, auth }) => {
    const created = await shopOrders(supabase).createFulfillment(orderId);

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok(created.data.id);
  },
);

export const shipFulfillment = bs.action(
  {
    input: v.object({ fulfillmentId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ fulfillmentId }, { supabase, auth }) => {
    const shipped = await shopOrders(supabase).shipFulfillment(fulfillmentId);

    if (!shipped.ok) {
      return shipped;
    }

    refreshCaller(auth);

    return ok(shipped.data);
  },
);

export const deliverFulfillment = bs.action(
  {
    input: v.object({ fulfillmentId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ fulfillmentId }, { supabase, auth }) => {
    const delivered =
      await shopOrders(supabase).deliverFulfillment(fulfillmentId);

    if (!delivered.ok) {
      return delivered;
    }

    refreshCaller(auth);

    return ok(delivered.data);
  },
);

const Code = v.pipe(
  v.string(),
  v.trim(),
  v.toUpperCase(),
  v.regex(/^[A-Z0-9_-]{3,32}$/, "Use 3 to 32 letters, digits, - or _"),
);

/** Applies a promotion code to the draft order's cart. */
export const applyPromotionCode = bs.action(
  {
    input: v.object({ cartId: Id, code: Code }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ cartId, code }, { supabase, auth }) => {
    const applied = await blocks(supabase).promotions.applyCode(cartId, code);

    if (!applied.ok) {
      return applied;
    }

    refreshCaller(auth);

    return ok(code);
  },
);

export const removePromotionCode = bs.action(
  {
    input: v.object({ cartId: Id, code: Code }),
    requireTenant: true,
    authorize: (session) => can(session, "orders.manage"),
  },
  async ({ cartId, code }, { supabase, auth }) => {
    const removed = await blocks(supabase).promotions.removeCode(cartId, code);

    if (!removed.ok) {
      return removed;
    }

    refreshCaller(auth);

    return ok(removed.data);
  },
);

/** Creates a percentage promotion with one code, such as `WELCOME10` for 10%. */
export const createPromotionCode = bs.action(
  {
    input: v.object({
      code: Code,
      percent: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^\d{1,3}(\.\d{1,2})?$/, "Enter a percentage such as 10"),
        v.check(
          (percent) => Number(percent) > 0 && Number(percent) <= 100,
          "Enter a percentage above 0 and at most 100",
        ),
      ),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "promotions.manage"),
  },
  async ({ code, percent }, { tenant, supabase }) => {
    const { promotions } = blocks(supabase);

    const promotion = await promotions.savePromotion(tenant, {
      name: `${code} (${percent}% off)`,
      discount: { kind: "percentage", percent },
    });

    if (!promotion.ok) {
      return promotion;
    }

    const codes = await promotions.createCodes(promotion.data.id, {
      codes: [code],
    });

    if (!codes.ok) {
      return codes;
    }

    return ok(code);
  },
);
