import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MemorySection,
  MemorySectionSkeleton,
} from "@/features/agents/components/memory-section";

export const ensureStatic = "prefetch";
export const instant = true;

export default function MemoryPage() {
  const t = useExtracted("agents");

  return (
    <>
      <PageHeader
        title={t("Memory")}
        description={t(
          "What the assistant knows about the organization: core files it reads every answer and facts it saved.",
        )}
      />
      <Suspense fallback={<MemorySectionSkeleton />}>
        <MemorySection />
      </Suspense>
    </>
  );
}
