import { Suspense } from "react";

import {
  BillingOverview,
  BillingOverviewSkeleton,
} from "@/features/billing/components/billing-overview";

export const instant = true;

export default function BillingSettingsPage() {
  return (
    <Suspense fallback={<BillingOverviewSkeleton />}>
      <BillingOverview />
    </Suspense>
  );
}
