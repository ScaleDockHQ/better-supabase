import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RiskHeatmap,
  RiskHeatmapSkeleton,
} from "@/features/risks/components/risk-heatmap";
import {
  RiskRegisterSectionSkeleton,
  RiskRegisterSection,
} from "@/features/risks/components/risk-register-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function RisksPage() {
  const t = useExtracted("risks");

  return (
    <>
      <PageHeader
        title={t("Risks")}
        description={t(
          "Where the open risks sit on the organization's matrix, and the register with each risk's residual rating and next review.",
        )}
      />
      <Suspense fallback={<RiskHeatmapSkeleton />}>
        <PermissionGate permission="risks.read">
          <RiskHeatmap />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<RiskRegisterSectionSkeleton />}>
        <PermissionGate permission="risks.read">
          <RiskRegisterSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
