import "server-only";
import { cacheLife } from "next/cache";

import { bs } from "@/lib/supabase/server";

export interface PlanOption {
  readonly key: string;
  readonly name: string;
  readonly priceCents: number;
  readonly features: readonly {
    readonly key: string;
    readonly value: unknown;
  }[];
}

/**
 * The plan catalog (`public.plans` and `public.plan_features`, which the
 * entitlements module reads). It is the same for every user, so it lives
 * in the shared cache: one user's first visit fills it for everyone, and
 * writes to `plans` expire it through the `plans` tag.
 */
export async function getPlans(): Promise<readonly PlanOption[]> {
  "use cache";
  cacheLife("hours");
  bs.cacheTag("plans");
  const plans = await bs
    .admin()
    .plans.findMany({
      select: ["key", "name", "priceCents"],
      include: {
        planFeatures: { select: ["featureKey", "included", "value"] },
      },
      orderBy: { position: "asc" },
    })
    .orThrow();
  return plans.map((plan) => ({
    key: plan.key,
    name: plan.name,
    priceCents: plan.priceCents,
    features: plan.planFeatures
      .filter((feature) => feature.included)
      .map((feature) => ({ key: feature.featureKey, value: feature.value })),
  }));
}

/** The organization's subscription; RLS limits it to members. */
export async function getSubscription(organizationId: string) {
  "use cache: private";
  const { db } = await bs.cached();
  return db.subscriptions
    .findFirst({
      select: ["planKey", "status", "currentPeriodEnd"],
      where: { organizationId },
    })
    .orThrow();
}
