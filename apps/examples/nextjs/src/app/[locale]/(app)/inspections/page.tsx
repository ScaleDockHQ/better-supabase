import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  InspectionProgramCalendarSectionSkeleton,
  InspectionProgramCalendarSection,
} from "@/features/inspections/components/inspection-program-calendar-section";
import {
  InspectionRunSectionSkeleton,
  InspectionRunSection,
} from "@/features/inspections/components/inspection-run-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function InspectionsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("inspections");

  return (
    <>
      <PageHeader
        title={t("Audits and inspections")}
        description={t(
          "The audit programme with each inspection's status, and the findings of the one you open, each nonconformity with its case.",
        )}
      />
      <Suspense fallback={<InspectionProgramCalendarSectionSkeleton />}>
        <PermissionGate permission="inspections.read">
          <InspectionProgramCalendarSection />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<InspectionRunSectionSkeleton />}>
        <PermissionGate permission="inspections.read">
          {searchParams.then((query) => (
            <InspectionRunSection query={query} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
