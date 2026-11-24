import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { InspectionOverview } from "@/features/inspections/components/inspection-overview";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function InspectionRegisterPage({
  searchParams,
}: PageProps<"/[locale]/inspections/register">) {
  const t = useExtracted("inspections");

  return (
    <>
      <PageHeader
        title={t("Inspection register")}
        description={t(
          "Every inspection with its status, searchable and paged.",
        )}
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <InspectionOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
