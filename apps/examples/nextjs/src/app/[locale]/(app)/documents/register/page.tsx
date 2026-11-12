import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RegisterOverview,
  RegisterOverviewSkeleton,
} from "@/features/document-register/components/register-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function DocumentRegisterPage() {
  const t = useExtracted("documents");

  return (
    <>
      <PageHeader
        title={t("Document register")}
        description={t(
          "Controlled documents with their number, effective version and review date.",
        )}
      />
      <Suspense fallback={<RegisterOverviewSkeleton />}>
        <PermissionGate permission="drive.read">
          <RegisterOverview />
        </PermissionGate>
      </Suspense>
    </>
  );
}
