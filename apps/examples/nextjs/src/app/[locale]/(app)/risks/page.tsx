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

// A prefetch of this page stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

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
