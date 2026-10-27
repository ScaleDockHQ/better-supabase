import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { ConnectivityFallback } from "@/features/offline/components/connectivity-fallback";
import {
  TaskViews,
  TaskViewsSkeleton,
} from "@/features/projects/components/task-views";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export default function ProjectsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("projects");

  return (
    <>
      <PageHeader
        title={t("Projects")}
        description={t(
          "One tasks table as a grid, a board, a calendar, a timeline and a Gantt chart.",
        )}
      />
      <Suspense
        fallback={
          <ConnectivityFallback>
            <TaskViewsSkeleton />
          </ConnectivityFallback>
        }
      >
        <TaskViews searchParams={searchParams} />
      </Suspense>
    </>
  );
}
