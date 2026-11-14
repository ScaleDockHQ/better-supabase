import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CareAlertsSectionSkeleton,
  CareAlertsSection,
} from "@/features/clinical-decision-support/components/care-alerts-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
