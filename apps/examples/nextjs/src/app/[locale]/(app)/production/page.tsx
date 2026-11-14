import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MaterialRequirementsSection,
  MaterialRequirementsSectionSkeleton,
} from "@/features/manufacturing/components/material-requirements-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ProductionPage() {
  const t = useExtracted("production");

  return (
    <>
      <PageHeader
        title={t("Production planning")}
        description={t(
          "Shortages from stock, demand and reorder points, turned into draft production orders and purchases.",
        )}
      />
      <Suspense fallback={<MaterialRequirementsSectionSkeleton />}>
        <PermissionGate permission="manufacturing.read">
          <MaterialRequirementsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
