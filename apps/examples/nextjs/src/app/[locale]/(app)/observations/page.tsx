import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ObservationChart,
  ObservationChartSkeleton,
} from "@/features/observations/components/observation-chart";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ObservationsPage() {
  const t = useExtracted("observations");

  return (
    <>
      <PageHeader
        title={t("Observations")}
        description={t(
          "A customer's latest vital signs, each flagged against its reference range, with the trend of its recent readings.",
        )}
      />
      <Suspense fallback={<ObservationChartSkeleton />}>
        <PermissionGate permission="observations.read">
          <ObservationChart />
        </PermissionGate>
      </Suspense>
    </>
  );
}
