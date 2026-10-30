import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AcknowledgementInbox,
  AcknowledgementInboxSkeleton,
} from "@/features/acknowledgements/components/acknowledgement-inbox";
import {
  ConsentRegister,
  ConsentRegisterSkeleton,
} from "@/features/compliance/components/consent-register";
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
          "What you are asked to read, how each framework's controls stand, the evidence that is due, the contracts coming up for renewal and what the organization asks consent for.",
        )}
      />
      <Suspense fallback={<AcknowledgementInboxSkeleton />}>
        <PermissionGate permission="acknowledgements.acknowledge">
          <AcknowledgementInbox />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<ControlPostureSkeleton />}>
        <PermissionGate permission="compliance.read">
          <ControlPosture />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<ContractRenewalsSkeleton />}>
        <PermissionGate permission="contracts.read">
          <ContractRenewals />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<ConsentRegisterSkeleton />}>
        <PermissionGate permission="consents.read">
          <ConsentRegister />
        </PermissionGate>
      </Suspense>
    </>
  );
}
