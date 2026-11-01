"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/**
 * Acknowledges a warning or info alert; a critical one needs an override
 * reason.
 */
export const acknowledgeCareAlert = bsb.action(
  {
    input: v.object({ alertId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "clinical_decision_support.write",
  },
  async ({ alertId }, { db }) => {
    const alert = await db.clinicalDecisionSupport.decide(
      alertId,
      "acknowledged",
    );

    return alert.ok ? ok({ id: alert.data.id }) : alert;
  },
);
