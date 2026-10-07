import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  OnboardingCard,
  OnboardingCardSkeleton,
} from "@/features/dashboard/components/onboarding-card";
import {
  UsageCard,
  UsageCardSkeleton,
} from "@/features/dashboard/components/usage-card";
import {
  WorkspaceSummary,
  WorkspaceSummarySkeleton,
} from "@/features/dashboard/components/workspace-summary";

export const instant = true;

/** Everything outside a `<Suspense>` boundary is the page's static shell. */
export default function DashboardPage() {
  const t = useExtracted("dashboard");
  return (
    <>
      <PageHeader
        title={t("Dashboard")}
        description={t("Your organization at a glance.")}
      />
      <Suspense fallback={<WorkspaceSummarySkeleton />}>
        <WorkspaceSummary />
      </Suspense>
      <div className="grid gap-6 lg:grid-cols-2">
        <Suspense fallback={<OnboardingCardSkeleton />}>
          <OnboardingCard />
        </Suspense>
        <Suspense fallback={<UsageCardSkeleton />}>
          <UsageCard />
        </Suspense>
      </div>
    </>
  );
}
