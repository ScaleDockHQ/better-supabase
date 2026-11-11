import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { FinanceOverviewPage } from "@/components/finance-pages/finance-pages";
import { PageHeader } from "@/components/page-header";
import {
  PayrollRuns,
  PayrollRunsSkeleton,
} from "@/features/payroll-export/components/payroll-runs";
import { PermissionGate } from "@/features/user/components/permission-gate";

// instant: this overview keeps its own header and sections (the page reads
// the signed-in user's permissions), so it doesn't export `instant`; the
// list and detail pages beside it do.

export default function PayrollPage() {
  const t = useExtracted("payroll-export");

  return (
    <>
      <PageHeader
        title={t("Payroll export")}
        description={t(
          "The worked and leave hours of each period, ready to hand to the payroll provider.",
        )}
      />
      <Suspense fallback={<PayrollRunsSkeleton />}>
        <PermissionGate permission="payroll_export.read">
          <PayrollRuns />
        </PermissionGate>
      </Suspense>
      <FinanceOverviewPage entity="payroll" embedded />
    </>
  );
}
