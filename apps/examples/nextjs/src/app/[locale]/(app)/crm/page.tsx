import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CrmDashboard,
  CrmDashboardSkeleton,
} from "@/features/sales/components/crm-dashboard";

// A navigation here shows the header and the dashboard frame at once; the
// figures render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function CrmPage() {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Sales")}
        description={t(
          "Your pipeline, forecast and closing deals at a glance.",
        )}
      />
      <Suspense fallback={<CrmDashboardSkeleton />}>
        <CrmDashboard />
      </Suspense>
    </>
  );
}
