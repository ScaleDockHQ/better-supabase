import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MaterialRequirementsSection,
  MaterialRequirementsSkeleton,
} from "@/features/manufacturing/components/material-requirements-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
      <Suspense fallback={<MaterialRequirementsSkeleton />}>
        <PermissionGate permission="manufacturing.read">
          <MaterialRequirementsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
