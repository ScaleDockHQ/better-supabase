"use client";

import type { JsonRenderSpec } from "better-supabase/json-render";

import { lazy, Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";

const SpecView = lazy(() =>
  import("./spec-view").then((mod) => ({ default: mod.SpecView })),
);

/** The json-render runtime loads after the first paint, behind a skeleton. */
export function SpecViewLazy({ spec }: { spec: JsonRenderSpec }) {
  return (
    <Suspense fallback={<SpecViewSkeleton />}>
      <SpecView spec={spec} />
    </Suspense>
  );
}

export function SpecViewSkeleton() {
  return (
    <div className="flex flex-col gap-2">
      <Skeleton className="h-5 w-40" />
      <Skeleton className="h-5 w-80 max-w-full" />
    </div>
  );
}
