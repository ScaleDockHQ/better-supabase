import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";
import { Suspense } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getPlans, getSubscription } from "../billing-queries";
import { MarkPlanReviewedButton } from "./mark-plan-reviewed-button";
import { PlanFeatures } from "./plan-features";

/** The caller's subscription; `null` outside an organization. */
async function currentSubscription() {
  const organizationId = tenantOf(await getSession());
  return organizationId ? getSubscription(organizationId) : null;
}

/**
 * Render inside `<Suspense>`. The example doesn't install the billing SQL
 * module (Stripe Checkout and webhooks), so plans are read-only here.
 */
export async function CurrentPlan() {
  const session = await getSession();
  const organizationId = tenantOf(session);
  if (!organizationId) return null;
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
      {can(session, "onboarding.complete") ? (
        <CardFooter>
          <MarkPlanReviewedButton />
        </CardFooter>
      ) : null}
    </Card>
  );
}

/** Marks the caller's plan; the card around it comes from the shared cache. */
async function PlanButton({ planKey }: { planKey: string }) {
  const [subscription, t] = await Promise.all([
    currentSubscription(),
    getExtracted("billing"),
  ]);
  const active = planKey === subscription?.planKey;
  return (
    <Button
      className="w-full"
      variant={active ? "secondary" : "default"}
      data-testid={active ? "active-plan" : undefined}
      disabled
    >
      {active ? t("Current plan") : t("Switch")}
    </Button>
  );
}

/**
 * The plan catalog from the shared cache: after the first visit by anyone,
 * it renders without a database round trip. Reading the session first keeps
 * it out of the build's prerender, which has no secret key or database.
 * Render inside `<Suspense>`.
 */
export async function PlanGrid() {
  if (!tenantOf(await getSession())) return null;
  const [plans, t, format] = await Promise.all([
    getPlans(),
    getExtracted("billing"),
    getFormatter(),
  ]);
  const price = (cents: number) =>
    cents === 0
      ? t("Free")
      : t("{price} per month", {
          price: format.number(cents / 100, {
            style: "currency",
            currency: "USD",
          }),
        });
  const featureLabel = ({
    key,
    value,
  }: (typeof plans)[number]["features"][number]) => {
    switch (key) {
      case "seats":
        return t("{seats} seats", { seats: String(value) });
      case "exports":
        return t("CSV exports");
      case "audit":
        return t("Audit log");
      case "sso":
        return t("Single sign-on");
      default:
        return key;
    }
  };

  return (
    <>
      <div className="grid gap-4 md:grid-cols-3">
        {plans.map((plan) => (
          <Card key={plan.key} size="sm" data-testid="plan">
            <CardHeader>
              <CardTitle>{plan.name}</CardTitle>
              <CardDescription>{price(plan.priceCents)}</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="text-muted-foreground space-y-1 text-sm">
                {plan.features.map((feature) => (
                  <li key={feature.key}>{featureLabel(feature)}</li>
                ))}
              </ul>
            </CardContent>
            <CardFooter>
              <Suspense
                fallback={
                  <Button className="w-full" disabled>
                    {t("Switch")}
                  </Button>
                }
              >
                <PlanButton planKey={plan.key} />
              </Suspense>
            </CardFooter>
          </Card>
        ))}
      </div>
      <p className="text-muted-foreground text-sm">
        {t(
          "Plan changes go through Stripe Checkout with the billing SQL module, which this example doesn't install.",
        )}
      </p>
    </>
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
