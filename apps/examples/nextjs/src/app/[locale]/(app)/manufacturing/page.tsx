import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ProductionOrderBoardSection,
  ProductionOrderBoardSkeleton,
} from "@/features/manufacturing/components/production-order-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function ManufacturingPage() {
  const t = useExtracted("manufacturing");

  return (
    <>
      <PageHeader
        title={t("Manufacturing")}
        description={t(
          "Production orders from draft to done, consuming components from stock and receiving the output at its cost.",
        )}
      />
      <Suspense fallback={<ProductionOrderBoardSkeleton />}>
        <PermissionGate permission="manufacturing.read">
          <ProductionOrderBoardSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
