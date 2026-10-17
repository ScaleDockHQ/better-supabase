// #region recipe:plan-picker
"use client";

import type { PlanCatalog } from "better-supabase/blocks/billing/react";

import { DbException } from "better-supabase";
import { usePlanPicker } from "better-supabase/blocks/billing/react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useErrorMessage } from "@/lib/use-error-message";

import type { PlanOption } from "../billing-queries";

import { loadPlanCatalog, startCheckout } from "../billing-actions";

async function loadCatalog(): Promise<PlanCatalog<PlanOption>> {
  const result = await loadPlanCatalog({});
  if (!result.ok) {
    throw new DbException(result.error);
  }
  return result.data;
}

/**
 * The plans with a checkout button each. The server renders the catalog;
 * `choose` runs the `startCheckout` server action, which talks to Stripe,
 * and sends the browser to the Checkout URL it returns.
 */
export function PlanPicker({
  initial,
  canManage,
}: {
  initial: PlanCatalog<PlanOption>;
  canManage: boolean;
}) {
  const t = useExtracted("billing");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const { plans, current, pending, choose } = usePlanPicker({
    load: loadCatalog,
    initial,
    checkout: (plan) => startCheckout({ plan }),
    open: (url) => {
      window.location.assign(url);
    },
  });
  const price = (cents: number) =>
    cents === 0
      ? t("Free")
      : t("{price} per month", {
          price: format.number(cents / 100, {
            style: "currency",
            currency: "USD",
          }),
        });
  const featureLabel = ({ key, value }: PlanOption["features"][number]) => {
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
    <div className="grid gap-4 md:grid-cols-3">
      {(plans ?? initial.plans).map((plan) => {
        const active = plan.key === current;
        return (
          <Card key={plan.key} size="sm" data-testid="plan">
            <CardHeader>
              <CardTitle>{plan.name}</CardTitle>
              <CardDescription>{price(plan.priceCents)}</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1 text-sm text-muted-foreground">
                {plan.features.map((feature) => (
                  <li key={feature.key}>{featureLabel(feature)}</li>
                ))}
              </ul>
            </CardContent>
            <CardFooter>
              <Button
                className="w-full"
                variant={active ? "secondary" : "default"}
                data-testid={active ? "active-plan" : undefined}
                disabled={active || !canManage || pending !== undefined}
                onClick={() => {
                  void choose(plan.key).then((started) => {
                    if (!started.ok) {
                      toast.error(errorMessage(started.error));
                    }
                  });
                }}
              >
                {active
                  ? t("Current plan")
                  : pending === plan.key
                    ? t("Opening checkout")
                    : t("Switch")}
              </Button>
            </CardFooter>
          </Card>
        );
      })}
    </div>
  );
}
// #endregion recipe:plan-picker
