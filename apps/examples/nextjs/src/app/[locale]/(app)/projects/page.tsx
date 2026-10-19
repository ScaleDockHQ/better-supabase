import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TaskViews,
  TaskViewsSkeleton,
} from "@/features/projects/components/task-views";

export const instant = true;

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
      <Suspense fallback={<TaskViewsSkeleton />}>
        <TaskViews searchParams={searchParams} />
      </Suspense>
    </>
  );
}
