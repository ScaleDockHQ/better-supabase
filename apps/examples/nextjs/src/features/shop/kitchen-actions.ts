"use server";

import { ok } from "better-supabase";
import { PREPARATION_STATES } from "better-supabase/blocks/orders";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { shopOrders } from "./shop-server";

const Id = v.pipe(v.string(), v.uuid());

async function canPrepare(): Promise<boolean> {
  const permissions = await getPermissions();

  return (
    can(permissions, "orders.prepare") || can(permissions, "orders.manage")
  );
}

/** Sends a paid order's lines to their stations as queued tickets. */
export const sendToKitchen = bsb.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    authorize: canPrepare,
  },
  async ({ orderId }, { supabase, auth }) => {
    const sent = await shopOrders(supabase).kitchen.send(orderId);

    if (!sent.ok) {
      return sent;
    }

    refreshCaller(auth);

    return ok(sent.data);
  },
);

/**
 * Moves an order's lines up to a state, at one station or at every station.
 * Lines already further along stay where they are.
 */
export const bumpTicket = bsb.action(
  {
    input: v.object({
      orderId: Id,
      state: v.picklist(PREPARATION_STATES),
      stationId: v.nullable(Id),
    }),
    requireTenant: true,
    authorize: canPrepare,
  },
  async ({ orderId, state, stationId }, { supabase, auth }) => {
    const bumped = await shopOrders(supabase).kitchen.bump(
      orderId,
      state,
      stationId ?? undefined,
    );

    if (!bumped.ok) {
      return bumped;
    }

    refreshCaller(auth);

    return ok(bumped.data);
  },
);

/** Sets one line's state, forward or back. */
export const setLineState = bsb.action(
  {
    input: v.object({ lineId: Id, state: v.picklist(PREPARATION_STATES) }),
    requireTenant: true,
    authorize: canPrepare,
  },
  async ({ lineId, state }, { supabase, auth }) => {
    const line = await shopOrders(supabase).kitchen.setState(lineId, state);

    if (!line.ok) {
      return line;
    }

    refreshCaller(auth);

    return ok(line.data.state);
  },
);
