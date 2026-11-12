import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ForecastOverview,
  ForecastOverviewSkeleton,
  SnapshotDialog,
} from "@/features/sales/components/pipeline-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function ForecastsPage({
  searchParams,
}: PageProps<"/[locale]/crm/forecasts">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Forecasts")}
        description={t(
          "Snapshots of the forecast call by period, so a review shows what changed.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="forecasts.snapshot">
              <SnapshotDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<ForecastOverviewSkeleton />}>
        {searchParams.then((raw) => (
          <ForecastOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
