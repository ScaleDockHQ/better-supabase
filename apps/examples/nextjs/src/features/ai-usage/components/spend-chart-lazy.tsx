"use client";

import { lazy, Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";

const SpendChart = lazy(() =>
  import("./spend-chart").then((mod) => ({ default: mod.SpendChart })),
);

/**
 * The chart's code (recharts) loads after the first paint, behind a skeleton of
 * its height.
 */
export function SpendChartLazy(props: {
  days: readonly { readonly day: string; readonly costUsd: number }[];
}) {
  return (
    <Suspense fallback={<Skeleton className="h-48 w-full" />}>
      <SpendChart {...props} />
    </Suspense>
  );
}
