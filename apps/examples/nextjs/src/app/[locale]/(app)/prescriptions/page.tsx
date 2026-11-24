import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  PrescriptionKpis,
  PrescriptionKpisSkeleton,
  PrescriptionOverview,
} from "@/features/e-prescribing/components/prescription-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header, the figure band and the list frame at
// once; the figures and the rows render on navigation.
export const instant = true;

export default function PrescriptionsPage({
  searchParams,
}: PageProps<"/[locale]/prescriptions">) {
  const t = useExtracted("prescriptions");

  return (
    <>
      <PageHeader
        title={t("Prescriptions")}
        description={t(
          "Drafts the prescriber signs, then a gateway sends them to the pharmacy.",
        )}
      />
      <Suspense fallback={<PrescriptionKpisSkeleton />}>
        <PermissionGate permission="e_prescribing.read">
          <PrescriptionKpis />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<RecordListSkeleton rows={4} />}>
        <PermissionGate permission="e_prescribing.read">
          {searchParams.then((raw) => (
            <PrescriptionOverview query={parseBlockList(raw)} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
