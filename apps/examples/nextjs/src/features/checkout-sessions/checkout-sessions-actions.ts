"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Cancels an open or ready session, so the agent can no longer complete it. */
export const cancelCheckoutSession = bsb.blockAction(
  ({ db }) => db.agentCheckout,
  "cancelSession",
  {
    input: v.object({ sessionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "agent_checkout.write",
    tags: () => [tags.agentCheckout()],
    refresh: true,
    args: ({ sessionId }) => [sessionId],
  },
  (canceled) => canceled.id,
);
