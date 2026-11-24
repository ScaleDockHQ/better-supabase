import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { ProductionOrderOverview } from "@/features/manufacturing/components/production-order-overview";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function ProductionOrdersPage({
  searchParams,
}: PageProps<"/[locale]/manufacturing/orders">) {
  const t = useExtracted("manufacturing");

  return (
    <>
      <PageHeader
        title={t("Production orders")}
        description={t(
          "Every order from draft to done, with its status counts.",
        )}
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <ProductionOrderOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
