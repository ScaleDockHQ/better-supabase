"use client";

import { lazy, Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";

const PassRateChart = lazy(() =>
  import("./pass-rate-chart").then((mod) => ({ default: mod.PassRateChart })),
);

/**
 * The chart's code (recharts) loads after the first paint, so the eval page's
 * first load stays small; a skeleton of the chart's height holds the space.
 */
export function PassRateChartLazy(props: {
  points: readonly { readonly label: string; readonly passRate: number }[];
}) {
  return (
    <Suspense fallback={<Skeleton className="h-48 w-full" />}>
      <PassRateChart {...props} />
    </Suspense>
  );
}
