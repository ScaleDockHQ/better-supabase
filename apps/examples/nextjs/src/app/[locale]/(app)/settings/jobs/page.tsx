import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  JobRunsTable,
  JobRunsTableSkeleton,
} from "@/features/jobs/components/job-runs-table";
import { Link } from "@/i18n/navigation";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function JobsSettingsPage() {
  const t = useExtracted("jobs");

  return (
    <>
      <div className="flex justify-end">
        <Link
          href="/settings/jobs/runs"
          className={buttonVariants({ variant: "outline", size: "sm" })}
        >
          {t("Search all runs")}
        </Link>
      </div>
      <Suspense fallback={<JobRunsTableSkeleton />}>
        <JobRunsTable />
      </Suspense>
    </>
  );
}
