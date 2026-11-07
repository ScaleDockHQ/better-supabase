import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  UsageRightsSectionSkeleton,
  UsageRightsSection,
} from "@/features/dam/components/usage-rights-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function DamPage() {
  const t = useExtracted("dam");

  return (
    <>
      <PageHeader
        title={t("Assets")}
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
