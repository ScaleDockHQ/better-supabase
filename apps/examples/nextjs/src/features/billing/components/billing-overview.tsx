import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";

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
import { cn } from "@/lib/utils";

import { getBilling } from "../billing-queries";
import { MarkPlanReviewedButton } from "./mark-plan-reviewed-button";
import { PlanFeatures } from "./plan-features";

/**
 * Render inside `<Suspense>`. The example doesn't install the billing SQL
 * module (Stripe Checkout and webhooks), so plans are read-only here.
 */
export async function BillingOverview() {
  const session = await getSession();
  const organizationId = tenantOf(session);
  if (!organizationId) return null;
  const [{ plans, subscription }, t, format] = await Promise.all([
    getBilling(organizationId),
    getExtracted("billing"),
    getFormatter(),
  ]);
  const current = plans.find((plan) => plan.key === subscription?.planKey);
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
      <Card>
        <CardHeader>
          <CardTitle>{t("Current plan")}</CardTitle>
          <CardDescription>
            {subscription?.currentPeriodEnd
              ? t("Renews {date}", {
                  date: format.dateTime(
                    new Date(subscription.currentPeriodEnd),
                    {
                      dateStyle: "long",
                    },
                  ),
                })
              : t("No renewal date")}
          </CardDescription>
          <CardAction>
            <Badge data-testid="current-plan">
              {current?.name ?? t("None")}
            </Badge>
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

      <div className="grid gap-4 md:grid-cols-3">
        {plans.map((plan) => {
          const active = plan.key === subscription?.planKey;
          return (
            <Card
              key={plan.key}
              size="sm"
              className={cn(active && "ring-primary ring-2")}
            >
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
                <Button
                  className="w-full"
                  variant={active ? "secondary" : "default"}
                  disabled
                >
                  {active ? t("Current plan") : t("Switch")}
                </Button>
              </CardFooter>
            </Card>
          );
        })}
      </div>
      <p className="text-muted-foreground text-sm">
        {t(
          "Plan changes go through Stripe Checkout with the billing SQL module, which this example doesn't install.",
        )}
      </p>
    </>
  );
}

export function BillingOverviewSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-56 rounded-xl" />
      <div className="grid gap-4 md:grid-cols-3">
        {Array.from({ length: 3 }, (_, index) => (
          <Skeleton key={index} className="h-48 rounded-xl" />
        ))}
      </div>
    </div>
  );
}
