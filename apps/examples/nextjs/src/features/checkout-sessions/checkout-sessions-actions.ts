"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { CHECKOUT_SESSIONS_TAG } from "./checkout-sessions-cache";

/** Cancels an open or ready session, so the agent can no longer complete it. */
export const cancelCheckoutSession = bsb.action(
  {
    input: v.object({ sessionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "agent_checkout.write",
  },
  async ({ sessionId }, { db, auth }) => {
    const canceled = await db.agentCheckout.cancelSession(sessionId);

    if (!canceled.ok) {
      return canceled;
    }

    await refreshCaller(auth, [CHECKOUT_SESSIONS_TAG]);

    return ok(canceled.data.id);
  },
);
