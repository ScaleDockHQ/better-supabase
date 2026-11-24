import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  CarePlanKpis,
  CarePlanKpisSkeleton,
  CarePlanOverview,
} from "@/features/care-plans/components/care-plan-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header, the figure band and the list frame at
// once; the figures and the rows render on navigation.
export const instant = true;

export default function CarePlansPage({
  searchParams,
}: PageProps<"/[locale]/care-plans">) {
  const t = useExtracted("care-plans");

  return (
    <>
      <PageHeader
        title={t("Care plans")}
        description={t(
          "A client's problems, goals and actions, from draft to the plan in use.",
        )}
      />
      <Suspense fallback={<CarePlanKpisSkeleton />}>
        <PermissionGate permission="care_plans.read">
          <CarePlanKpis />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<RecordListSkeleton rows={4} />}>
        <PermissionGate permission="care_plans.read">
          {searchParams.then((raw) => (
            <CarePlanOverview query={parseBlockList(raw)} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
