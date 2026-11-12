import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  BillingAccount,
  BillingAccountSkeleton,
} from "@/features/billing-account/components/billing-account";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function BillingAccountPage() {
  const t = useExtracted("billingAccount");

  return (
    <>
      <PageHeader
        title={t("Billing account")}
        description={t(
          "The Stripe customer, seats and invoices of this organization, read through the billing block.",
        )}
      />
      <Suspense fallback={<BillingAccountSkeleton />}>
        <PermissionGate permission="billing.read">
          <BillingAccount />
        </PermissionGate>
      </Suspense>
    </>
  );
}
