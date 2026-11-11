import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  RunQueue,
  RunQueueSkeleton,
} from "@/features/agents/components/run-queue";

export const ensureStatic = "prefetch";
export const instant = true;

export default function RunsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/agents/runs">) {
  const t = useExtracted("agents");

  return (
    <>
      <PageHeader
        title={t("Run queue")}
        description={t(
          "Every generation, grouped by state. Open a failed run to triage it.",
        )}
      />
      <Suspense fallback={<RunQueueSkeleton />}>
        <RunQueue query={loadOpsList(searchParams)} />
      </Suspense>
    </>
  );
}
