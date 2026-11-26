"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Releases a draft order; the database refuses when a component is short. */
export const releaseProductionOrder = bsb.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    permission: "manufacturing.write",
    tags: () => [tags.manufacturing(), tags.shop()],
    refresh: true,
  },
  async ({ orderId }, { db }) => {
    const released = await db.manufacturing.release({ orderId });

    if (!released.ok) {
      return released;
    }

    return ok({ id: released.data.id, status: released.data.status });
  },
);

/**
 * Turns every current shortage into a draft production order or purchase order,
 * or a purchase requisition when the block's `purchaseSuggestions` is
 * `requisition`.
 */
export const createFromRequirements = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "manufacturing.write",
    tags: () => [tags.manufacturing(), tags.shop()],
    refresh: true,
  },
  async (_input, { db }) => {
    const requirements = await db.manufacturing.requirements();

    if (!requirements.ok) {
      return requirements;
    }

    const items = requirements.data.items.map(
      ({ variantId, action, quantity }) => ({ variantId, action, quantity }),
    );

    if (items.length === 0) {
      return ok({ productionOrders: 0, purchases: 0 });
    }

    const created = await db.manufacturing.createFromRequirements(items);

    if (!created.ok) {
      return created;
    }

    return ok({
      productionOrders: created.data.productionOrders.length,
      purchases:
        created.data.purchaseOrders.length +
        created.data.purchaseRequisitions.length,
    });
  },
);

/** Completes an order with its planned quantity, backflushing the rest. */
export const completeProductionOrder = bsb.action(
  {
    input: v.object({
      orderId: Id,
      produced: v.pipe(v.number(), v.gtValue(0)),
    }),
    requireTenant: true,
    permission: "manufacturing.produce",
    tags: () => [tags.manufacturing(), tags.shop()],
    refresh: true,
  },
  async ({ orderId, produced }, { db }) => {
    const done = await db.manufacturing.complete({ orderId, produced });

    if (!done.ok) {
      return done;
    }

    return ok({ id: done.data.id, status: done.data.status });
  },
);
