"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { MANUFACTURING_TAG } from "@/features/manufacturing/manufacturing-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { Decimal, Id, given, Name, Optional, Whole } from "@/lib/form-input";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { WAREHOUSE_TAG } from "./warehouse-cache";

const TAGS = [WAREHOUSE_TAG, SHOP_TAG, MANUFACTURING_TAG];

/** Finishes a pick list: lines with less picked than asked for become short. */
export const completePickList = bsb.action(
  {
    input: v.object({ pickListId: Id }),
    requireTenant: true,
    permission: "warehouse.pick",
  },
  async ({ pickListId }, { db, auth }) => {
    const done = await db.warehouse.completePickList(pickListId);

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, TAGS);

    return ok({ status: done.data.status });
  },
);

/** Records what a picker found on one line. */
export const recordPick = bsb.action(
  {
    input: v.object({ lineId: Id, quantity: Decimal }),
    requireTenant: true,
    permission: "warehouse.pick",
  },
  async ({ lineId, quantity }, { db, auth }) => {
    const picked = await db.warehouse.recordPick({
      lineId,
      pick: { quantity: Number(quantity) },
    });

    if (!picked.ok) {
      return picked;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/**
 * Orders an open pick list by the bins' walking ranks, so the picker walks the
 * aisle once. A real warehouse would map bins to coordinates instead.
 */
export const optimizePickRoute = bsb.action(
  {
    input: v.object({ pickListId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async ({ pickListId }, { db, auth }) => {
    const list = await db.warehouse.getPickList(pickListId);

    if (!list.ok) {
      return list;
    }

    const slots = await db.warehouse.listBinSlots(list.data.locationId);

    if (!slots.ok) {
      return slots;
    }

    const rankOf = new Map(
      slots.data.map((slot) => [slot.binId, slot.walkRank]),
    );

    const routed = await db.warehouse.optimizePickRoute({
      pickListId,
      locate: (line) => {
        const rank =
          line.binId === undefined ? undefined : rankOf.get(line.binId);

        return rank === undefined
          ? undefined
          : { latitude: 0, longitude: rank };
      },
      start: { latitude: 0, longitude: 0 },
    });

    if (!routed.ok) {
      return routed;
    }

    await refreshCaller(auth, TAGS);

    return ok({ source: routed.data.optimization.source });
  },
);

export const createPickWave = bsb.action(
  {
    input: v.object({ name: Name, locationId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async (input, { db, auth }) => {
    const wave = await db.warehouse.createPickWave(input);

    if (!wave.ok) {
      return wave;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: wave.data.id });
  },
);

/** Releases a draft wave or cancels a draft or released one. */
export const transitionWave = bsb.action(
  {
    input: v.object({ waveId: Id, action: v.picklist(["release", "cancel"]) }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async ({ waveId, action }, { db, auth }) => {
    const moved =
      action === "release"
        ? await db.warehouse.releasePickWave(waveId)
        : await db.warehouse.cancelPickWave(waveId);

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const savePutawayRule = bsb.action(
  {
    input: v.object({
      locationId: Id,
      binId: Id,
      variantId: Optional,
      priority: Optional,
      maxQuantity: Optional,
    }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async (input, { db, auth }) => {
    const priority = Number(input.priority ?? "10");
    const max = Number(input.maxQuantity);

    const saved = await db.warehouse.savePutawayRule({
      locationId: input.locationId,
      binId: input.binId,
      ...given("variantId", input.variantId),
      ...given("priority", Number.isInteger(priority) ? priority : undefined),
      ...given(
        "maxQuantity",
        Number.isFinite(max) && max > 0 ? max : undefined,
      ),
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

export const deletePutawayRule = bsb.action(
  {
    input: v.object({ ruleId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async ({ ruleId }, { db, auth }) => {
    const removed = await db.warehouse.deletePutawayRule(ruleId);

    if (!removed.ok) {
      return removed;
    }

    await refreshCaller(auth, TAGS);

    return ok(removed.data);
  },
);

export const createCountPlan = bsb.action(
  {
    input: v.object({
      name: Name,
      locationId: Id,
      everyDays: Whole(1, 365),
      varianceLimitPct: Optional,
    }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async (input, { db, auth }) => {
    const limit = Number(input.varianceLimitPct);

    const plan = await db.warehouse.createCountPlan({
      name: input.name,
      locationId: input.locationId,
      everyDays: input.everyDays,
      ...given(
        "varianceLimitPct",
        Number.isFinite(limit) && limit >= 0 ? limit : undefined,
      ),
    });

    if (!plan.ok) {
      return plan;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: plan.data.id });
  },
);

/** Opens the count of one plan now, or of every plan that is due. */
export const runCountPlans = bsb.action(
  {
    input: v.object({ planId: Optional }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async ({ planId }, { db, auth }) => {
    const opened =
      planId === undefined
        ? await db.warehouse.runDueCountPlans()
        : await db.warehouse.runCountPlan(planId);

    if (!opened.ok) {
      return opened;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Posts a cycle count; one over the plan's variance limit needs `approve`. */
export const postCycleCount = bsb.action(
  {
    input: v.object({ countId: Id, approve: v.optional(v.boolean(), false) }),
    requireTenant: true,
    permission: "warehouse.manage",
  },
  async ({ countId, approve }, { db, auth }) => {
    const posted = await db.warehouse.postCycleCount({ countId, approve });

    if (!posted.ok) {
      return posted;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);
