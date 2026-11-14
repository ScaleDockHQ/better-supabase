import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  UsageRightsSectionSkeleton,
  UsageRightsSection,
} from "@/features/dam/components/usage-rights-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function DamPage() {
  const t = useExtracted("dam");

  return (
    <>
      <PageHeader
        title={t("Digital assets")}
        description={t("Who may use your files, where, and until when.")}
      />
      <Suspense fallback={<UsageRightsSectionSkeleton />}>
        <PermissionGate permission="dam.read">
          <UsageRightsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
