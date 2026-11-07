import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getCareAlerts } from "@/features/clinical-decision-support/clinical-decision-support-queries";
import { CareAlerts } from "@/features/clinical-decision-support/components/care-alerts";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function CareAlertsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <CareAlerts
      state={await getCareAlerts()}
      canDecide={can(permissions, "clinical_decision_support.write")}
    />
  );
}

export function CareAlertsSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
