import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DeadlineOverview,
  DeadlineOverviewSkeleton,
} from "@/features/deadlines/components/deadline-overview";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function DeadlinesPage() {
  const t = useExtracted("work");

  return (
    <>
      <PageHeader
        title={t("Deadlines")}
        description={t(
          "Due dates computed from approved rules, and the ones still open.",
        )}
      />
      <Suspense fallback={<DeadlineOverviewSkeleton />}>
        <DeadlineOverview />
      </Suspense>
    </>
  );
}
