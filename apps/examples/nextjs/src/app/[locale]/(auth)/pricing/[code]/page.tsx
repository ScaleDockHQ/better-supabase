import { generatePermutations } from "flags/next";
import { getExtracted } from "next-intl/server";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { env } from "@/env";
import { pricingBanner, pricingFlags } from "@/flags";

/** The code the proxy rewrites to when FLAGS_SECRET isn't set. */
const DEFAULTS = "default";

/**
 * Every combination of the precomputed flags is a static page. Cache Components
 * needs at least one param, so without the secret the page is built once with
 * the flags' defaults.
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
 * code, so it never reads cookies or headers.
 */
export default async function PricingPage({
  params,
}: PageProps<"/[locale]/pricing/[code]">) {
  const { code } = await params;

  const [showBanner, t] = await Promise.all([
    code === DEFAULTS ? false : pricingBanner(code, pricingFlags),
    getExtracted("pricing"),
  ]);

  return (
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
  );
}
