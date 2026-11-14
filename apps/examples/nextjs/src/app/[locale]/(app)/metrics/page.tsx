import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MetricsDashboard,
  MetricsDashboardSkeleton,
} from "@/features/metrics/components/metrics-dashboard";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
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
