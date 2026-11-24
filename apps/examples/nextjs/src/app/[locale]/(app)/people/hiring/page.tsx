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
  HiringBoard,
  HiringBoardSkeleton,
} from "@/features/people/components/hiring-board";
import {
  ApplicationOverview,
  HiringKpis,
} from "@/features/people/components/hiring-overviews";
import { parseBlockList } from "@/lib/block-overview-query";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function HiringPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Hiring")}
        description={t("Openings and their candidates by interview stage.")}
      />
      <Suspense fallback={<HiringBoardSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["board", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch
                base="/people/hiring"
                active={view}
                views={views}
              />
              {view === "table" ? (
                <>
                  <Suspense fallback={<KpiBandSkeleton />}>
                    <HiringKpis />
                  </Suspense>
                  <Suspense fallback={<RecordListSkeleton rows={4} />}>
                    <ApplicationOverview query={parseBlockList(raw)} />
                  </Suspense>
                </>
              ) : (
                <HiringBoard query={raw} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
