import "server-only";
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
 * entitlements module reads) and the organization's subscription.
 */
export async function getBilling(organizationId: string) {
  "use cache: private";
  const { db } = await bs.cached();
  const [plans, subscription] = await Promise.all([
    db.plans
      .findMany({
        select: ["key", "name", "priceCents"],
        include: {
          planFeatures: { select: ["featureKey", "included", "value"] },
        },
        orderBy: { position: "asc" },
      })
      .orThrow(),
    db.subscriptions
      .findFirst({
        select: ["planKey", "status", "currentPeriodEnd"],
        where: { organizationId },
      })
      .orThrow(),
  ]);
  return {
    plans: plans.map((plan): PlanOption => ({
      key: plan.key,
      name: plan.name,
      priceCents: plan.priceCents,
      features: plan.planFeatures
        .filter((feature) => feature.included)
        .map((feature) => ({ key: feature.featureKey, value: feature.value })),
    })),
    subscription,
  };
}
