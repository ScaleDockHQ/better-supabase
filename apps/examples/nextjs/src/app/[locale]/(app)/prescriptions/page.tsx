import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  PrescriptionsSectionSkeleton,
  PrescriptionsSection,
} from "@/features/e-prescribing/components/prescriptions-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function PrescriptionsPage() {
  const t = useExtracted("prescriptions");

  return (
    <>
      <PageHeader
        title={t("Prescriptions")}
        description={t(
          "Drafts the prescriber signs, then a gateway sends them to the pharmacy.",
        )}
      />
      <Suspense fallback={<PrescriptionsSectionSkeleton />}>
        <PermissionGate permission="e_prescribing.read">
          <PrescriptionsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
