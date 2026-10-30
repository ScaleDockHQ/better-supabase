import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RiskHeatmap,
  RiskHeatmapSkeleton,
} from "@/features/risks/components/risk-heatmap";
import {
  RiskRegister,
  RiskRegisterSkeleton,
} from "@/features/risks/components/risk-register";
import { getRiskRegister } from "@/features/risks/risks-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";

async function Register() {
  return <RiskRegister state={await getRiskRegister()} />;
}

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
      <Suspense fallback={<RiskRegisterSkeleton />}>
        <PermissionGate permission="risks.read">
          <Register />
        </PermissionGate>
      </Suspense>
    </>
  );
}
