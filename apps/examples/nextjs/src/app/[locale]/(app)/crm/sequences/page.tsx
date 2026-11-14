import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import { SequenceOverview } from "@/features/sequences/components/sequence-overview";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function SequencesPage({
  searchParams,
}: PageProps<"/[locale]/crm/sequences">) {
  const t = useExtracted("sequences");

  return (
    <>
      <PageHeader
        title={t("Sequences")}
        description={t(
          "Email, wait and task steps that run for each enrolled contact until they reply.",
        )}
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <SequenceOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
