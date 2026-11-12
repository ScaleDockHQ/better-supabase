import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { PermissionGate } from "@/features/user/components/permission-gate";
import {
  RunsList,
  RunsListSkeleton,
} from "@/features/workflows/components/runs-list";
import { ScheduleForm } from "@/features/workflows/components/schedule-controls";
import {
  ScheduleList,
  ScheduleListSkeleton,
} from "@/features/workflows/components/schedule-list";
import { WorkflowActions } from "@/features/workflows/components/workflow-actions";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// A navigation here paints the header and the list skeleton at once
// (tests/loading-sequences.spec.ts).
export const instant = true;

export default function WorkflowRunsPage() {
  const t = useExtracted("workflows");

  return (
    <>
      <PageHeader
        title={t("Workflow runs")}
        description={t(
          "Every run of the organization, newest first. The list reloads while runs change.",
        )}
        actions={<WorkflowActions />}
      />
      <div data-recipe="workflow-runs">
        <Suspense fallback={<RunsListSkeleton />}>
          <PermissionGate permission="workflows.read">
            <RunsList />
          </PermissionGate>
        </Suspense>
      </div>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("Schedules")}</h2>
        <Suspense fallback={<ScheduleListSkeleton />}>
          <ScheduleList />
        </Suspense>
        <ScheduleForm />
      </section>
    </>
  );
}
