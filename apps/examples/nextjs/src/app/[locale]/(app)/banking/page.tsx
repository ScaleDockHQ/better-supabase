import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  BankReconciliation,
  BankReconciliationSkeleton,
} from "@/features/banking/components/bank-reconciliation";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function BankingPage() {
  const t = useExtracted("banking");

  return (
    <>
      <PageHeader
        title={t("Banking")}
        description={t(
          "Imported bank statements matched to invoices and booked through the journals, account by account.",
        )}
      />
      <Suspense fallback={<BankReconciliationSkeleton />}>
        <PermissionGate permission="banking.read">
          <BankReconciliation />
        </PermissionGate>
      </Suspense>
    </>
  );
}
