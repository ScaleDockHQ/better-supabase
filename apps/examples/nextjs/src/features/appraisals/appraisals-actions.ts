"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/**
 * Signs an appraisal off. With the approvals block the sign-off waits for its
 * approval.
 */
export const signOffAppraisal = bsb.action(
  {
    input: v.object({ appraisalId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "appraisals.manage",
  },
  async ({ appraisalId }, { db }) => {
    const signed = await db.appraisals.signOff(appraisalId);

    return signed.ok ? ok({ status: signed.data.status }) : signed;
  },
);
