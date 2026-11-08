import { FlagValues } from "flags/react";
import { getExtracted } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { pricingBanner, pricingFlags } from "@/flags";

/** The code the proxy rewrites to when FLAGS_SECRET isn't set. */
export const PRICING_DEFAULTS = "default";

/**
 * Render inside `<Suspense>`: the pricing card for one precomputed flag code.
 * It reads the flags from the code, never from cookies or headers, so the page
 * stays static.
 */
export async function PricingCard({ code }: { code: string }) {
  const [showBanner, t] = await Promise.all([
    code === PRICING_DEFAULTS
      ? pricingBanner.defaultValue
      : pricingBanner(code, pricingFlags),
    getExtracted("pricing"),
  ]);

  return (
    <div className="flex flex-col gap-6">
      <Card data-testid="pricing">
        <CardHeader>
          <CardTitle>{t("Pricing")}</CardTitle>
          <CardDescription>
            {t("One plan per organization, billed monthly.")}
          </CardDescription>
        </CardHeader>
        {showBanner ? (
          <Alert data-testid="pricing-banner">
            <AlertTitle>{t("Upgrade and save")}</AlertTitle>
            <AlertDescription>
              {t("The pricing-banner flag is on for your plan.")}
            </AlertDescription>
          </Alert>
        ) : null}
      </Card>
      <FlagValues values={{ [pricingBanner.key]: showBanner }} />
    </div>
  );
}

export function PricingCardSkeleton() {
  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <Skeleton className="h-5 w-24" />
          <Skeleton className="h-4 w-64" />
        </CardHeader>
      </Card>
    </div>
  );
}
