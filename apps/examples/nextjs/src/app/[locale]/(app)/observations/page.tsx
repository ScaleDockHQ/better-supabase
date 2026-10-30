import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ObservationChart,
  ObservationChartSkeleton,
} from "@/features/observations/components/observation-chart";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
