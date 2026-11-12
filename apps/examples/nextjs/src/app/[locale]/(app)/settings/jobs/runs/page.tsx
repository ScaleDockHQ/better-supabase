import { Suspense } from "react";

import {
  JobRunList,
  JobRunListSkeleton,
} from "@/features/jobs/components/job-run-list";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

export default function JobRunsPage() {
  return (
    <Suspense fallback={<JobRunListSkeleton />}>
      <JobRunList />
    </Suspense>
  );
}
