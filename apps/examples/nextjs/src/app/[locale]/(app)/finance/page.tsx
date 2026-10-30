import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TrialBalance,
  TrialBalanceSkeleton,
} from "@/features/accounting/components/trial-balance";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function FinancePage() {
  const t = useExtracted("accounting");

  return (
    <>
      <PageHeader
        title={t("Finance")}
        description={t(
          "The balance sheet totals, this year's net income and the trial balance of the posted entries.",
        )}
      />
      <Suspense fallback={<TrialBalanceSkeleton />}>
        <PermissionGate permission="accounting.read">
          <TrialBalance />
        </PermissionGate>
      </Suspense>
    </>
  );
}
