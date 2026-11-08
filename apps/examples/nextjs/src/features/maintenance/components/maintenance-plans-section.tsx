import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { MaintenancePlans } from "@/features/maintenance/components/maintenance-plans";
import { getMaintenancePlans } from "@/features/maintenance/maintenance-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function MaintenancePlansSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <MaintenancePlans
      state={await getMaintenancePlans()}
      canManage={can(permissions, "maintenance.manage")}
    />
  );
}

export function MaintenancePlansSectionSkeleton() {
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
