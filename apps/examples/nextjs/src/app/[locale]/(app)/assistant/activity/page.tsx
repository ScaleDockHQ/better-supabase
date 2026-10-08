import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AgentActivity,
  AgentActivitySkeleton,
} from "@/features/assistant/components/agent-activity";

export const instant = true;

export default function AgentActivityPage() {
  const t = useExtracted("assistant");
  return (
    <>
      <PageHeader
        title={t("Agent activity")}
        description={t(
          "Runs from ai_runs with their steps, and the tool calls waiting for your approval.",
        )}
      />
      <Suspense fallback={<AgentActivitySkeleton />}>
        <AgentActivity />
      </Suspense>
    </>
  );
}
