import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  EmployeeOverview,
  EmployeeOverviewSkeleton,
} from "@/features/people/components/employee-overview";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function PeoplePage() {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("People")}
        description={t("Your organization's employees and who they report to.")}
      />
      <Suspense fallback={<EmployeeOverviewSkeleton />}>
        <EmployeeOverview />
      </Suspense>
    </>
  );
}
