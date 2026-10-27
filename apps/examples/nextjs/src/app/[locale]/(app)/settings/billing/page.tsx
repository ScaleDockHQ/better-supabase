import { Suspense } from "react";

import {
  CurrentPlan,
  CurrentPlanSkeleton,
  PlanGrid,
  PlanGridSkeleton,
} from "@/features/billing/components/billing-overview";
import {
  InvoicesTable,
  InvoicesTableSkeleton,
} from "@/features/billing/components/invoices-table";

export default function BillingSettingsPage() {
  return (
    <div className="space-y-6">
      <Suspense fallback={<CurrentPlanSkeleton />}>
        <CurrentPlan />
      </Suspense>
      <Suspense fallback={<PlanGridSkeleton />}>
        <PlanGrid />
      </Suspense>
      <Suspense fallback={<InvoicesTableSkeleton />}>
        <InvoicesTable />
      </Suspense>
    </div>
  );
}
