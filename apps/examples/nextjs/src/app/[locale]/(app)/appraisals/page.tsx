import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AppraisalListSectionSkeleton,
  AppraisalListSection,
} from "@/features/appraisals/components/appraisal-list-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function AppraisalsPage() {
  const t = useExtracted("appraisals");

  return (
    <>
      <PageHeader
        title={t("Appraisals")}
        description={t(
          "Review cycles with self, peer and manager reviews, calibration and sign-off.",
        )}
      />
      <Suspense fallback={<AppraisalListSectionSkeleton />}>
        <PermissionGate permission="appraisals.review">
          <AppraisalListSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
