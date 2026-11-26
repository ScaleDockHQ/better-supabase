"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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

    await refreshCaller(auth, [tags.agentCheckout()]);

    return ok(canceled.data.id);
  },
);
