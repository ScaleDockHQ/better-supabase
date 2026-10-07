"use server";

import { dbError, err, ok } from "better-supabase";
import { toSession } from "better-supabase/next";
import { refresh } from "next/cache";

import { activeOrganizationId, can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** Completes the "Review your plan" onboarding step. */
export const markPlanReviewed = bs.action(
  {},
  async (_input, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "onboarding.complete")) {
      return err(dbError("forbidden", "You cannot complete onboarding steps"));
    }
    const completed = await blocks(supabase).onboarding.complete(
      "plan",
      organizationId,
    );
    if (!completed.ok) return completed;
    refresh();
    return ok(completed.data);
  },
);
