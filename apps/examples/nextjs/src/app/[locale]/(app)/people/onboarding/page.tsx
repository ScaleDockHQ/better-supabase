import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  OnboardingOverview,
  OnboardingOverviewSkeleton,
} from "@/features/onboarding/components/onboarding-overview";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function OnboardingPage() {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Onboarding")}
        description={t(
          "New hires and the steps they finish in their first weeks.",
        )}
      />
      <Suspense fallback={<OnboardingOverviewSkeleton />}>
        <OnboardingOverview />
      </Suspense>
    </>
  );
}
