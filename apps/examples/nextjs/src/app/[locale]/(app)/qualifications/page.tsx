import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MyQualifications,
  MyQualificationsSkeleton,
} from "@/features/qualifications/components/my-qualifications";
import {
  QualificationMatrix,
  QualificationMatrixSkeleton,
} from "@/features/qualifications/components/qualification-matrix";
import {
  QualificationTypeOverview,
  QualificationTypeOverviewSkeleton,
} from "@/features/qualifications/components/qualification-type-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of this page stays static; the lists render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function QualificationsPage() {
  const t = useExtracted("qualifications");

  return (
    <>
      <PageHeader
        title={t("Qualifications")}
        description={t(
          "The certificates and licences members hold, and the required ones that are missing or about to expire.",
        )}
      />
      <Suspense fallback={<QualificationTypeOverviewSkeleton />}>
        <PermissionGate permission="qualifications.read">
          <QualificationTypeOverview />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<QualificationMatrixSkeleton />}>
        <PermissionGate permission="qualifications.read">
          <QualificationMatrix />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<MyQualificationsSkeleton />}>
        <MyQualifications />
      </Suspense>
    </>
  );
}
