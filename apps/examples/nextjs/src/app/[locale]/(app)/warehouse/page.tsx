import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { PermissionGate } from "@/features/user/components/permission-gate";
import {
  PickListGridSectionSkeleton,
  PickListGridSection,
} from "@/features/warehouse/components/pick-list-grid-section";

export default function WarehousePage() {
  const t = useExtracted("warehouse");

  return (
    <>
      <PageHeader
        title={t("Warehouse")}
        description={t(
          "Pick lists made from stock allocations, with the stock to take from each bin.",
        )}
      />
      <Suspense fallback={<PickListGridSectionSkeleton />}>
        <PermissionGate permission="warehouse.pick">
          <PickListGridSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
