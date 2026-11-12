import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  PipelineOverview,
  PipelineOverviewSkeleton,
} from "@/features/sales/components/pipeline-overviews";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function PipelinesPage({
  searchParams,
}: PageProps<"/[locale]/crm/pipelines">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Pipelines")}
        description={t(
          "The stages a deal moves through, and how many deals sit in each.",
        )}
      />
      <Suspense fallback={<PipelineOverviewSkeleton />}>
        {searchParams.then((raw) => (
          <PipelineOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
