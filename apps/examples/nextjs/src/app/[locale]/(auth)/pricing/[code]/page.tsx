import { generatePermutations } from "flags/next";
import { FlagValues } from "flags/react";
import { getExtracted } from "next-intl/server";
import { Suspense } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { env } from "@/env";
import {
  CurrentPlan,
  CurrentPlanSkeleton,
} from "@/features/billing/components/billing-overview";
import { pricingBanner, pricingFlags } from "@/flags";

/** The code the proxy rewrites to when FLAGS_SECRET isn't set. */
const DEFAULTS = "default";

/**
 * Every combination of the precomputed flags is a static page. Cache Components
 * rejects an empty list, so without the secret the page is built once with the
 * flags' declared defaults.
 */
export async function generateStaticParams() {
  if (!env.FLAGS_SECRET) {
    return [{ code: DEFAULTS }];
  }

  const codes = await generatePermutations(pricingFlags);

  return codes.map((code) => ({ code }));
}

/**
 * `/pricing` is rewritten here by the proxy, which evaluates the flags for the
 * visitor's organization and plan (`precompute`). The page reads them from the
 * code, so its shell is static; only the signed-in plan streams in.
 */
export default async function PricingPage({
  params,
}: PageProps<"/[locale]/pricing/[code]">) {
  const { code } = await params;

  const [showBanner, t] = await Promise.all([
    code === DEFAULTS
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
      <Suspense fallback={<CurrentPlanSkeleton />}>
        <CurrentPlan />
      </Suspense>
      <FlagValues values={{ [pricingBanner.key]: showBanner }} />
    </div>
  );
}
