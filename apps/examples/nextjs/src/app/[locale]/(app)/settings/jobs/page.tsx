import { Suspense } from "react";

import {
  JobRunsTable,
  JobRunsTableSkeleton,
} from "@/features/jobs/components/job-runs-table";

export default function JobsSettingsPage() {
  return (
    <Suspense fallback={<JobRunsTableSkeleton />}>
      <JobRunsTable />
    </Suspense>
  );
}
