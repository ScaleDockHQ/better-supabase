import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { AiTaskQueueSkeleton } from "@/features/ai-tasks/components/ai-task-queue";
import { AiTaskSection } from "@/features/ai-tasks/components/ai-task-section";

export const instant = true;

export default function AiTasksPage() {
  const t = useExtracted("aiTasks");

  return (
    <>
      <PageHeader
        title={t("AI tasks")}
        description={t(
          "Prompts on the ai-tasks block that the assistant runs on a schedule.",
        )}
      />
      <Suspense fallback={<AiTaskQueueSkeleton />}>
        <AiTaskSection />
      </Suspense>
    </>
  );
}
