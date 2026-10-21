// #region recipe:plan-picker
"use client";

import type { PlanCatalog } from "better-supabase/blocks/billing/react";
import type { Money } from "better-supabase/commerce";

import { DbException } from "better-supabase";
import { usePlanPicker } from "better-supabase/blocks/billing/react";
import { formatMoney } from "better-supabase/commerce";
import { useExtracted, useLocale } from "next-intl";
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
 * `choose` runs the `startCheckout` server action, which talks to Stripe, and
 * sends the browser to the Checkout URL it returns.
 */
export function PlanPicker({
  initial,
  canManage,
}: {
  initial: PlanCatalog<PlanOption>;
  canManage: boolean;
}) {
  const t = useExtracted("billing");
  const locale = useLocale();
  const errorMessage = useErrorMessage();

  const { plans, current, pending, choose } = usePlanPicker({
    load: loadCatalog,
    initial,
    checkout: (plan) => startCheckout({ plan }),
    open: (url) => {
      window.location.assign(url);
    },
  });

  const price = (value: Money) =>
    value.amount === 0n
      ? t("Free")
      : t("{price} per month", { price: formatMoney(value, locale) });

  const featureLabel = ({ key, value }: PlanOption["features"][number]) => {
    switch (key) {
      case "seats": {
        return t("{seats} seats", { seats: String(value) });
      }

      case "exports": {
        return t("CSV exports");
      }

      case "audit": {
        return t("Audit log");
      }

      case "sso": {
        return t("Single sign-on");
      }

      default: {
        return key;
      }
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
              <CardDescription>{price(plan.price)}</CardDescription>
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
