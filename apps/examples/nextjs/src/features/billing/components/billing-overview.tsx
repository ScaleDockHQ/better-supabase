import type { ComponentProps } from "react";

import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";
import { Suspense } from "react";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getPlans, getSubscription } from "../billing-queries";
import { MarkPlanReviewedButton } from "./mark-plan-reviewed-button";
import { PlanFeatures } from "./plan-features";
import { PlanPicker } from "./plan-picker";

/**
 * Render inside `<Suspense>`. The example doesn't install the billing SQL
 * module (Stripe Checkout and webhooks), so the plan comes from the seeded
 * subscription.
 */
export async function CurrentPlan() {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [subscription, plans, t, format] = await Promise.all([
    getSubscription(organizationId),
    getPlans(),
    getExtracted("billing"),
    getFormatter(),
  ]);

  const current = plans.find((plan) => plan.key === subscription?.planKey);

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Current plan")}</CardTitle>
        <CardDescription>
          {subscription?.currentPeriodEnd
            ? t("Renews {date}", {
                date: format.dateTime(new Date(subscription.currentPeriodEnd), {
                  dateStyle: "long",
                }),
              })
            : t("No renewal date")}
        </CardDescription>
        <CardAction>
          <Badge data-testid="current-plan">{current?.name ?? t("None")}</Badge>
        </CardAction>
      </CardHeader>
      <CardContent>
        <PlanFeatures />
      </CardContent>
      {can(permissions, "onboarding.complete") ? (
        <CardFooter>
          <MarkPlanReviewedButton />
        </CardFooter>
      ) : null}
    </Card>
  );
}

/**
 * The plan catalog from the shared cache, with the organization's plan:
 * `PlanPicker` starts from both. Reading the session first keeps it out of the
 * build's prerender, which has no secret key or database. Render inside
 * `<Suspense>`.
 */
export async function PlanGrid() {
  const session = await getSession();
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [plans, subscription, t] = await Promise.all([
    getPlans(),
    getSubscription(organizationId),
    getExtracted("billing"),
  ]);

  const initial = { plans, current: subscription?.planKey };

  return (
    <>
      <div data-recipe="plan-picker">
        <Suspense fallback={<PlanPicker initial={initial} canManage={false} />}>
          <ManagedPlanPicker initial={initial} />
        </Suspense>
      </div>
      <p className="text-sm text-muted-foreground">
        {t(
          "Plan changes go through Stripe Checkout with the billing SQL module, which this example doesn't install.",
        )}
      </p>
    </>
  );
}

/**
 * The permission is a private database read, so the plans render first with
 * switching off and this swaps in once the caller's keys arrive.
 */
async function ManagedPlanPicker({
  initial,
}: Pick<ComponentProps<typeof PlanPicker>, "initial">) {
  const permissions = await getPermissions();

  return (
    <PlanPicker
      initial={initial}
      canManage={can(permissions, "billing.manage")}
    />
  );
}

export function CurrentPlanSkeleton() {
  return <Skeleton className="h-56 rounded-xl" aria-busy="true" />;
}

export function PlanGridSkeleton() {
  return (
    <div aria-busy="true">
      <div className="grid gap-4 md:grid-cols-3">
        {Array.from({ length: 3 }, (_, index) => (
          <Skeleton key={index} className="h-48 rounded-xl" />
        ))}
      </div>
    </div>
  );
}
