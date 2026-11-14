import { CoinsIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
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
import { Link } from "@/i18n/navigation";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function BillingSettingsPage() {
  const t = useExtracted("billing");

  return (
    <div className="space-y-6">
      <Link
        href="/settings/billing/credits"
        className={buttonVariants({
          variant: "outline",
          size: "sm",
          className: "w-fit",
        })}
      >
        <CoinsIcon />
        {t("Credit ledger")}
      </Link>
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
