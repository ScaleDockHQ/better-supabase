import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { ScheduleForm } from "@/features/workflows/components/schedule-controls";
import {
  ScheduleList,
  ScheduleListSkeleton,
} from "@/features/workflows/components/schedule-list";
import { TenantWorkflowRuns } from "@/features/workflows/components/tenant-workflow-runs";
import { WorkflowActions } from "@/features/workflows/components/workflow-actions";
import { WorkflowRunsSkeleton } from "@/features/workflows/components/workflow-runs";

export const instant = true;

export default function WorkflowsPage() {
  const t = useExtracted("workflows");
  return (
    <>
      <PageHeader
        title={t("Workflows")}
        description={t(
          "Durable runs on the Workflow SDK with the Supabase World. The list stays live over Realtime.",
        )}
        actions={<WorkflowActions />}
      />
      <Suspense fallback={<WorkflowRunsSkeleton />}>
        <TenantWorkflowRuns />
      </Suspense>
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">{t("Schedules")}</h2>
        <Suspense fallback={<ScheduleListSkeleton />}>
          <ScheduleList />
        </Suspense>
        <ScheduleForm />
      </section>
    </>
  );
}
