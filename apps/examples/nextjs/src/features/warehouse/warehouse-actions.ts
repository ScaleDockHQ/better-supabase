"use server";

import { err, invalidInput, ok } from "better-supabase";
import * as v from "valibot";

import { Decimal, Id, given, Name, Optional, Whole } from "@/lib/form-input";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import { openOrderLines } from "./warehouse-queries";

const TAGS = [tags.warehouse(), tags.shop(), tags.manufacturing()];

/** Finishes a pick list: lines with less picked than asked for become short. */
export const completePickList = bsb.blockAction(
  ({ db }) => db.warehouse,
  "completePickList",
  {
    input: v.object({ pickListId: Id }),
    requireTenant: true,
    permission: "warehouse.pick",
    tags: () => TAGS,
    refresh: true,
    args: ({ pickListId }) => [pickListId],
  },
  (done) => ({ status: done.status }),
);

/** Records what a picker found on one line. */
export const recordPick = bsb.blockAction(
  ({ db }) => db.warehouse,
  "recordPick",
  {
    input: v.object({ lineId: Id, quantity: Decimal }),
    requireTenant: true,
    permission: "warehouse.pick",
    tags: () => TAGS,
    refresh: true,
    args: ({ lineId, quantity }) => [
      { lineId, pick: { quantity: Number(quantity) } },
    ],
  },
  () => true,
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
    tags: () => TAGS,
    refresh: true,
  },
  async ({ pickListId }, { db }) => {
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

    return ok({ source: routed.data.optimization.source });
  },
);

export const createPickWave = bsb.blockAction(
  ({ db }) => db.warehouse,
  "createPickWave",
  {
    input: v.object({ name: Name, locationId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
  },
  (wave) => ({ id: wave.id }),
);

/** Releases a draft wave or cancels a draft or released one. */
export const transitionWave = bsb.action(
  {
    input: v.object({ waveId: Id, action: v.picklist(["release", "cancel"]) }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ waveId, action }, { db }) => {
    const moved =
      action === "release"
        ? await db.warehouse.releasePickWave(waveId)
        : await db.warehouse.cancelPickWave(waveId);

    if (!moved.ok) {
      return moved;
    }

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
    tags: () => TAGS,
    refresh: true,
  },
  async (input, { db }) => {
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

    return ok({ id: saved.data.id });
  },
);

export const deletePutawayRule = bsb.blockAction(
  ({ db }) => db.warehouse,
  "deletePutawayRule",
  {
    input: v.object({ ruleId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ ruleId }) => [ruleId],
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
    tags: () => TAGS,
    refresh: true,
  },
  async (input, { db }) => {
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

    return ok({ id: plan.data.id });
  },
);

/** Opens the count of one plan now, or of every plan that is due. */
export const runCountPlans = bsb.action(
  {
    input: v.object({ planId: Optional }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ planId }, { db }) => {
    const opened =
      planId === undefined
        ? await db.warehouse.runDueCountPlans()
        : await db.warehouse.runCountPlan(planId);

    if (!opened.ok) {
      return opened;
    }

    return ok(true);
  },
);

/** Posts a cycle count; one over the plan's variance limit needs `approve`. */
export const postCycleCount = bsb.blockAction(
  ({ db }) => db.warehouse,
  "postCycleCount",
  {
    input: v.object({ countId: Id, approve: v.optional(v.boolean(), false) }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

/**
 * Holds stock of a variant for a document line; what isn't available waits on
 * backorder. A pick list is made from a document's open allocations (EX-1110).
 */
export const createAllocation = bsb.blockAction(
  ({ db }) => db.inventory,
  "allocate",
  {
    input: v.object({
      variantId: Id,
      locationId: Id,
      quantity: Decimal,
      documentType: Name,
      documentId: Id,
    }),
    requireTenant: true,
    permission: "inventory.reserve",
    tags: () => TAGS,
    refresh: true,
    args: (input, { tenant: organizationId }) => [
      {
        organizationId,
        input: {
          variantId: input.variantId,
          locationId: input.locationId,
          quantity: Number(input.quantity),
          documentType: input.documentType,
          documentId: input.documentId,
          lineId: crypto.randomUUID(),
        },
      },
    ],
  },
  (allocated) => ({ id: allocated.id }),
);

/** Makes a pick list from the open allocations of one document. */
export const createPickList = bsb.blockAction(
  ({ db }) => db.warehouse,
  "createPickList",
  {
    input: v.object({ locationId: Id, documentType: Name, documentId: Id }),
    requireTenant: true,
    permission: "warehouse.manage",
    tags: () => TAGS,
    refresh: true,
  },
  (list) => ({ id: list.id }),
);

/**
 * Receives what a placed purchase order still owes, line by line, into one
 * goods receipt that the putaway tab then suggests bins for (EX-1111).
 */
export const receiveOrder = bsb.action(
  {
    input: v.object({ purchaseOrderId: Id }),
    requireTenant: true,
    permission: "inventory.purchase",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ purchaseOrderId }, { db }) => {
    const lines = await openOrderLines(purchaseOrderId);

    if (lines.length === 0) {
      return err(
        invalidInput("Nothing is left to receive on this order.", [
          {
            path: ["purchaseOrderId"],
            code: "ORDER_FULLY_RECEIVED",
            message: "Pick an order that still owes units.",
          },
        ]),
      );
    }

    const received = await db.inventory.receivePurchaseOrder({
      purchaseOrderId,
      lines,
    });

    if (!received.ok) {
      return received;
    }

    return ok({ receiptId: received.data.receiptId ?? null });
  },
);
