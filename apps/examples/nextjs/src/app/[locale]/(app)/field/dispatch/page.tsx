import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  DispatchBoard,
  DispatchBoardSkeleton,
} from "@/features/field/components/dispatch-board";
import {
  FieldListSkeleton,
  WorkOrderKpis,
  WorkOrderOverview,
} from "@/features/field/components/field-overviews";
import { parseBlockList } from "@/lib/block-overview-query";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function DispatchPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("field");

  return (
    <>
      <PageHeader
        title={t("Dispatch")}
        description={t(
          "Schedule work orders into technicians' days and keep the backlog moving.",
        )}
      />
      <Suspense fallback={<DispatchBoardSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["board", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch
                base="/field/dispatch"
                active={view}
                views={views}
              />
              {view === "table" ? (
                <>
                  <Suspense fallback={<KpiBandSkeleton />}>
                    <WorkOrderKpis />
                  </Suspense>
                  <Suspense fallback={<FieldListSkeleton />}>
                    <WorkOrderOverview query={parseBlockList(raw)} />
                  </Suspense>
                </>
              ) : (
                <DispatchBoard query={raw} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
