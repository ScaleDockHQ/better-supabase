import { generatePermutations } from "flags/next";
import { Suspense } from "react";

import { env } from "@/env";
import {
  PRICING_DEFAULTS,
  PricingCard,
  PricingCardSkeleton,
} from "@/features/flags/components/pricing-card";
import { pricingFlags } from "@/flags";

/**
 * Every combination of the precomputed flags is a static page. Cache Components
 * rejects an empty list, so without the secret the page is built once with the
 * flags' declared defaults.
 */
export async function generateStaticParams() {
  if (!env.FLAGS_SECRET) {
    return [{ code: PRICING_DEFAULTS }];
  }

  const codes = await generatePermutations(pricingFlags);

  return codes.map((code) => ({ code }));
}

/**
 * `/pricing` is rewritten here by the proxy, which evaluates the flags for the
 * visitor's organization and plan (`precompute`). The page reads them from the
 * code, so it never reads cookies or headers and stays static.
 */
export default function PricingPage({
  params,
}: PageProps<"/[locale]/pricing/[code]">) {
  return (
    <Suspense fallback={<PricingCardSkeleton />}>
      {params.then(({ code }) => (
        <PricingCard code={code} />
      ))}
    </Suspense>
  );
}
