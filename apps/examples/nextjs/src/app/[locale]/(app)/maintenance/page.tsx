import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MaintenancePlansSectionSkeleton,
  MaintenancePlansSection,
} from "@/features/maintenance/components/maintenance-plans-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function MaintenancePage() {
  const t = useExtracted("maintenance");

  return (
    <>
      <PageHeader
        title={t("Maintenance")}
        description={t(
          "Preventive plans by time or meter, and the work orders they open.",
        )}
      />
      <Suspense fallback={<MaintenancePlansSectionSkeleton />}>
        <PermissionGate permission="maintenance.read">
          <MaintenancePlansSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
