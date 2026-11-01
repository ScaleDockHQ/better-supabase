"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Finishes a pick list: lines with less picked than asked for become short. */
export const completePickList = bsb.action(
  {
    input: v.object({ pickListId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "warehouse.pick",
  },
  async ({ pickListId }, { db }) => {
    const done = await db.warehouse.completePickList(pickListId);

    return done.ok ? ok({ status: done.data.status }) : done;
  },
);

/**
 * Orders an open pick list by the bins' walking ranks, so the picker walks the
 * aisle once. A real warehouse would map bins to coordinates instead.
 */
export const optimizePickRoute = bsb.action(
  {
    input: v.object({ pickListId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "warehouse.manage",
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

    const routed = await db.warehouse.optimizePickRoute(pickListId, {
      locate: (line) => {
        const rank =
          line.binId === undefined ? undefined : rankOf.get(line.binId);

        return rank === undefined
          ? undefined
          : { latitude: 0, longitude: rank };
      },
      start: { latitude: 0, longitude: 0 },
    });

    return routed.ok ? ok({ source: routed.data.optimization.source }) : routed;
  },
);
