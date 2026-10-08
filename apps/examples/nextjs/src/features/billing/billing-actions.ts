"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** Completes the "Review your plan" onboarding step. */
export const markPlanReviewed = bs.action(
  {
    requireTenant: true,
    authorize: (session) => can(session, "onboarding.complete"),
  },
  async (_input, { tenant: organizationId, supabase }) => {
    const completed = await blocks(supabase).onboarding.complete(
      "plan",
      organizationId,
    );
    if (!completed.ok) return completed;
    refresh();
    return ok(completed.data);
  },
);
