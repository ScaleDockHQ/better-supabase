"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Releases a draft order; the database refuses when a component is short. */
export const releaseProductionOrder = bsb.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    permission: "manufacturing.write",
  },
  async ({ orderId }, { db, auth }) => {
    const released = await db.manufacturing.release(orderId);

    if (!released.ok) {
      return released;
    }

    await refreshCaller(auth);

    return ok({ id: released.data.id, status: released.data.status });
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
  },
  async ({ orderId, produced }, { db, auth }) => {
    const done = await db.manufacturing.complete(orderId, produced);

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth);

    return ok({ id: done.data.id, status: done.data.status });
  },
);
