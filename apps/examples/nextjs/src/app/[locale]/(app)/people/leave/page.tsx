import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  LeaveOverview,
  LeaveOverviewSkeleton,
} from "@/features/leave/components/leave-overview";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

export default function LeavePage() {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Leave")}
        description={t(
          "Time off by type, requests approved by a manager, and your balances.",
        )}
      />
      <Suspense fallback={<LeaveOverviewSkeleton />}>
        <LeaveOverview />
      </Suspense>
    </>
  );
}
