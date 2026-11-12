import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  IncidentList,
  IncidentListSkeleton,
} from "@/features/incidents/components/incident-list";
import { OpenIncidentDialog } from "@/features/incidents/components/open-incident-dialog";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function IncidentsPage() {
  const t = useExtracted("incidents");

  return (
    <>
      <PageHeader
        title={t("Incidents")}
        description={t(
          "What broke, how bad it is and what the team did about it, from the first report to the postmortem.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="incidents.write">
              <OpenIncidentDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<IncidentListSkeleton />}>
        <PermissionGate permission="incidents.read">
          <IncidentList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
