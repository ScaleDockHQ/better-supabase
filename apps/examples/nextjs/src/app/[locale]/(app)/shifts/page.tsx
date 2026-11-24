import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  RosterBoard,
  RosterBoardSkeleton,
} from "@/features/shifts/components/roster-board";
import {
  ShiftKpis,
  ShiftTable,
} from "@/features/shifts/components/shift-overviews";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ShiftsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("shifts");

  return (
    <>
      <PageHeader
        title={t("Shifts")}
        description={t(
          "Who works when this week, with the open places on each shift.",
        )}
      />
      <Suspense fallback={<RosterBoardSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["calendar", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch base="/shifts" active={view} views={views} />
              <Suspense fallback={<KpiBandSkeleton />}>
                <ShiftKpis />
              </Suspense>
              {view === "table" ? (
                <Suspense fallback={<RecordListSkeleton rows={4} />}>
                  <ShiftTable />
                </Suspense>
              ) : (
                <Suspense fallback={<RosterBoardSkeleton />}>
                  <RosterBoard />
                </Suspense>
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
