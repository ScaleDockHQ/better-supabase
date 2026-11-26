"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Cancels an open or ready session, so the agent can no longer complete it. */
export const cancelCheckoutSession = bsb.action(
  {
    input: v.object({ sessionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "agent_checkout.write",
    tags: () => [tags.agentCheckout()],
    refresh: true,
  },
  async ({ sessionId }, { db }) => {
    const canceled = await db.agentCheckout.cancelSession(sessionId);

    if (!canceled.ok) {
      return canceled;
    }

    return ok(canceled.data.id);
  },
);
