"use server";

import type { Result } from "better-supabase";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { gettingStarted } from "@/features/onboarding/checklist";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import type { PlanOption } from "./billing-queries";

import { getPlans } from "./billing-queries";

/** Completes the "Review your plan" onboarding step. */
export const markPlanReviewed = bsb.action(
  {
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "onboarding.complete"),
  },
  async (_input, { tenant: organizationId, db }) => {
    const completed = await db.onboarding.complete(
      gettingStarted,
      "plan",
      organizationId,
    );

    if (!completed.ok) {
      return completed;
    }

    refresh();

    return ok(completed.data);
  },
);

/** The plan catalog and the organization's plan, for `usePlanPicker`. */
export const loadPlanCatalog = bsb.action(
  {
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "billing.read"),
  },
  async (_input, { tenant: organizationId, db }) => {
    const plans = await getPlans();

    return db.subscriptions
      .get(
        { where: { organizationId } },
        { select: ["planKey"], optional: true },
      )
      .map((subscription) => ({ plans, current: subscription?.planKey }));
  },
);

/**
 * Starts Stripe Checkout for a plan of the fixture's catalog (`public.plans`).
 * It runs on the server, so the Stripe key never reaches the browser: with the
 * billing SQL module and a test-mode key (`sk_test_...`), it returns
 * `billing.checkout(organizationId, { plan, successUrl, cancelUrl })`. This
 * example installs neither, so it answers `unsupported`.
 */
export const startCheckout = bsb.action(
  {
    input: v.object({ plan: v.string() }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "billing.manage"),
  },
  async ({ plan }): Promise<Result<{ url: string | undefined }>> => {
    const plans: readonly PlanOption[] = await getPlans();

    if (!plans.some((each) => each.key === plan)) {
      return err(dbError("not_found", `There is no "${plan}" plan`));
    }

    return err(
      dbError(
        "unsupported",
        "Checkout needs the billing SQL module and a Stripe test key, which this example doesn't install.",
      ),
    );
  },
);
