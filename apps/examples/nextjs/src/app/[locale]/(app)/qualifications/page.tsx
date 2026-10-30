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
import { PermissionGate } from "@/features/user/components/permission-gate";

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
