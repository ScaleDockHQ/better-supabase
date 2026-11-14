import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AiTaskSectionSkeleton,
  AiTaskSection,
} from "@/features/ai-tasks/components/ai-task-section";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function AiTasksPage() {
  const t = useExtracted("aiTasks");

  return (
    <>
      <PageHeader
        title={t("AI tasks")}
        description={t(
          "Prompts on the ai-schedules block that the assistant runs on a schedule.",
        )}
      />
      <Suspense fallback={<AiTaskSectionSkeleton />}>
        <AiTaskSection />
      </Suspense>
    </>
  );
}
