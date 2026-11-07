import { io } from "next/cache";

import { getCareAlerts } from "@/features/clinical-decision-support/clinical-decision-support-queries";
import { CareAlerts } from "@/features/clinical-decision-support/components/care-alerts";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function CareAlertsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <CareAlerts
      state={await getCareAlerts()}
      canDecide={can(permissions, "clinical_decision_support.write")}
    />
  );
}
