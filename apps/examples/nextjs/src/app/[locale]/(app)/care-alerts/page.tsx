import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { getCareAlerts } from "@/features/clinical-decision-support/care-alerts-queries";
import {
  CareAlerts,
  CareAlertsSkeleton,
} from "@/features/clinical-decision-support/components/care-alerts";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function AlertList() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <CareAlerts
      state={await getCareAlerts()}
      canDecide={can(permissions, "clinical_decision_support.write")}
    />
  );
}

export default function CareAlertsPage() {
  const t = useExtracted("care-alerts");

  return (
    <>
      <PageHeader
        title={t("Care alerts")}
        description={t(
          "Dose range, duplicate therapy and interaction alerts on medication orders.",
        )}
      />
      <Suspense fallback={<CareAlertsSkeleton />}>
        <PermissionGate permission="clinical_decision_support.read">
          <AlertList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
