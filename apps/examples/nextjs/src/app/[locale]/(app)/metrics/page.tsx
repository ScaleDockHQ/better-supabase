import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MetricsDashboard,
  MetricsDashboardSkeleton,
} from "@/features/metrics/components/metrics-dashboard";

export const instant = true;

export default function MetricsPage() {
  const t = useExtracted("metrics");

  return (
    <>
      <PageHeader
        title={t("Metrics")}
        description={t("Your organization's numbers over the last 30 days.")}
      />
      <div data-recipe="metrics-dashboard">
        <Suspense fallback={<MetricsDashboardSkeleton />}>
          <MetricsDashboard />
        </Suspense>
      </div>
    </>
  );
}
