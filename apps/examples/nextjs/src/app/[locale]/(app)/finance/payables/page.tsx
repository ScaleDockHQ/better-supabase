import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  PayablesAgingSection,
  PayablesAgingSkeleton,
} from "@/features/payables/components/payables-aging";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function PayablesPage() {
  const t = useExtracted("payables");

  return (
    <>
      <PageHeader
        title={t("Payables")}
        description={t(
          "What you owe suppliers on issued purchase bills, by days past due.",
        )}
      />
      <Suspense fallback={<PayablesAgingSkeleton />}>
        <PermissionGate permission="invoices.read">
          <PayablesAgingSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
