"use server";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/**
 * Acknowledges a warning or info alert; a critical one needs an override
 * reason.
 */
export const acknowledgeCareAlert = bsb.blockAction(
  ({ db }) => db.clinicalDecisionSupport,
  "decide",
  {
    input: v.object({ alertId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "clinical_decision_support.write",
    args: ({ alertId }) => [{ alertId, decision: "acknowledged" }],
  },
  (alert) => ({ id: alert.id }),
);
