import { io } from "next/cache";

import { MaintenancePlans } from "@/features/maintenance/components/maintenance-plans";
import { getMaintenancePlans } from "@/features/maintenance/maintenance-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function MaintenancePlansSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <MaintenancePlans
      state={await getMaintenancePlans()}
      canManage={can(permissions, "maintenance.manage")}
    />
  );
}
