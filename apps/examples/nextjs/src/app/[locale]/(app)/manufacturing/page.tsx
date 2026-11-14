import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ProductionOrderBoardSection,
  ProductionOrderBoardSectionSkeleton,
} from "@/features/manufacturing/components/production-order-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
      <Suspense fallback={<ProductionOrderBoardSectionSkeleton />}>
        <PermissionGate permission="manufacturing.read">
          <ProductionOrderBoardSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
