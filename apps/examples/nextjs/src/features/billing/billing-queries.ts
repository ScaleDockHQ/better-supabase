import "server-only";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { cacheLife } from "next/cache";

import { bsb } from "@/lib/supabase/server";

export interface PlanOption {
  readonly key: string;
  readonly name: string;
  /** The monthly price. */
  readonly price: Money;
  readonly features: readonly {
    readonly key: string;
    readonly value: unknown;
  }[];
}

/**
 * The plan catalog (`public.plans` and `public.plan_features`, which the
 * entitlements module reads). It is the same for every user, so it lives in the
 * shared cache: one user's first visit fills it for everyone, and writes to
 * `plans` expire it through the `plans` tag.
 */
export async function getPlans(): Promise<readonly PlanOption[]> {
  "use cache";
  cacheLife("hours");
  bsb.tag("plans");

  const plans = await bsb
    .admin()
    .plans.list({
      select: ["key", "name", "priceCents", "currency"],
      include: {
        planFeatures: { select: ["featureKey", "included", "value"] },
      },
      orderBy: { position: "asc" },
    })
    .orThrow();

  return plans.map((plan) => ({
    key: plan.key,
    name: plan.name,
    price: money(plan.priceCents, plan.currency),
    features: plan.planFeatures
      .filter((feature) => feature.included)
      .map((feature) => ({ key: feature.featureKey, value: feature.value })),
  }));
}

/** The organization's subscription; RLS limits it to members. */
export async function getSubscription(organizationId: string) {
  "use cache: private";
  const { db } = await bsb.cached();

  return db.subscriptions
    .get(
      { where: { organizationId } },
      { select: ["planKey", "status", "currentPeriodEnd"], optional: true },
    )
    .orThrow();
}
