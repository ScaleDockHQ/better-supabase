"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { DUNNING_TAG } from "./dunning-cache";

/**
 * A reminder a week after the due date, a second with a 15.00 fee after three
 * weeks and a final notice with a 40.00 fee after 45 days.
 */
const STANDARD_LEVELS = [
  { daysAfterDue: 7, templateKey: "dunning.reminder" },
  { daysAfterDue: 21, templateKey: "dunning.second-reminder", fee: 1500n },
  {
    daysAfterDue: 45,
    templateKey: "dunning.final-notice",
    fee: 4000n,
    final: true,
  },
] as const;

/** Replaces the organization's reminder levels with the standard three. */
export const applyStandardDunningLevels = bsb.action(
  { input: v.object({}), requireTenant: true, permission: "invoices.manage" },
  async (_input, { tenant, db, auth }) => {
    const saved = await db.invoices.setDunningLevels({
      organizationId: tenant,
      levels: STANDARD_LEVELS,
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, [DUNNING_TAG]);

    return ok({ levels: saved.data.length });
  },
);
