import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  EmployeeOverview,
  EmployeeOverviewSkeleton,
} from "@/features/people/components/employee-overview";
import {
  EmployeeKpis,
  EmployeeStatusBoard,
  OnboardEmployeeDialog,
} from "@/features/people/components/employee-overviews";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function PeoplePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("People")}
        description={t("Your organization's employees and who they report to.")}
        actions={
          <Suspense>
            <OnboardEmployeeDialog />
          </Suspense>
        }
      />
      <Suspense fallback={<EmployeeOverviewSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["table", "board"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch base="/people" active={view} views={views} />
              <Suspense fallback={<KpiBandSkeleton />}>
                <EmployeeKpis />
              </Suspense>
              <Suspense fallback={<EmployeeOverviewSkeleton />}>
                {view === "board" ? (
                  <EmployeeStatusBoard />
                ) : (
                  <EmployeeOverview />
                )}
              </Suspense>
            </>
          );
        })}
      </Suspense>
    </>
  );
}
