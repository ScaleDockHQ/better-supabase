import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import {
  DealBoard,
  DealBoardSkeleton,
} from "@/features/crm/components/deal-board";
import {
  TargetsProgress,
  TargetsProgressSkeleton,
} from "@/features/crm/components/targets-progress";
import {
  DealOverview,
  DealOverviewSkeleton,
} from "@/features/sales/components/pipeline-overviews";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header, the view switch and the list frame at
// once; the rows render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function DealsPage({
  searchParams,
}: PageProps<"/[locale]/crm/deals">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Deals")}
        description={t(
          "Your pipeline by stage, and how the targets are going.",
        )}
      />
      <Suspense fallback={<TargetsProgressSkeleton />}>
        <TargetsProgress />
      </Suspense>
      <Suspense fallback={<DealOverviewSkeleton />}>
        {searchParams.then((raw) => {
          const view = activeTab(raw, ["table", "board"]);

          return (
            <>
              <RecordDetailTabs
                base="/crm/deals"
                active={view}
                tabs={[
                  { value: "table", label: t("Table") },
                  { value: "board", label: t("Board") },
                ]}
              />
              {view === "board" ? (
                <Suspense fallback={<DealBoardSkeleton />}>
                  <DealBoard />
                </Suspense>
              ) : (
                <DealOverview query={parseBlockList(raw)} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
