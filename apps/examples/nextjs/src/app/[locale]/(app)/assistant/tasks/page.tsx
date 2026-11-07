import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AiTaskSectionSkeleton,
  AiTaskSection,
} from "@/features/ai-tasks/components/ai-task-section";

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
