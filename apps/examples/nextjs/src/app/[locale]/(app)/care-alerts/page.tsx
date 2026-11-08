import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CareAlertsSectionSkeleton,
  CareAlertsSection,
} from "@/features/clinical-decision-support/components/care-alerts-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function CareAlertsPage() {
  const t = useExtracted("care-alerts");

  return (
    <>
      <PageHeader
        title={t("Care alerts")}
        description={t(
          "Dose range, duplicate therapy and interaction alerts on medication orders.",
        )}
      />
      <Suspense fallback={<CareAlertsSectionSkeleton />}>
        <PermissionGate permission="clinical_decision_support.read">
          <CareAlertsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
