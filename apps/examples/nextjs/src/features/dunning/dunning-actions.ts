"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
export const applyStandardDunningLevels = bsb.blockAction(
  ({ db }) => db.invoices,
  "setDunningLevels",
  {
    input: v.object({}),
    requireTenant: true,
    permission: "invoices.manage",
    tags: () => [tags.dunning()],
    refresh: true,
    args: (_, { tenant }) => [
      { organizationId: tenant, levels: STANDARD_LEVELS },
    ],
  },
  (saved) => ({ levels: saved.length }),
);
