import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ContractRenewals,
  ContractRenewalsSkeleton,
} from "@/features/compliance/components/contract-renewals";
import {
  ControlPosture,
  ControlPostureSkeleton,
} from "@/features/compliance/components/control-posture";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function CompliancePage() {
  const t = useExtracted("compliance");

  return (
    <>
      <PageHeader
        title={t("Compliance")}
        description={t(
          "How each framework's controls stand, the evidence that is due, and the contracts coming up for renewal.",
        )}
      />
      <Suspense fallback={<ControlPostureSkeleton />}>
        <PermissionGate permission="controls.read">
          <ControlPosture />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<ContractRenewalsSkeleton />}>
        <PermissionGate permission="contracts.read">
          <ContractRenewals />
        </PermissionGate>
      </Suspense>
    </>
  );
}
