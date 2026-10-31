import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MaintenancePlans,
  MaintenancePlansSkeleton,
} from "@/features/maintenance/components/maintenance-plans";
import { getMaintenancePlans } from "@/features/maintenance/maintenance-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function Plans() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <MaintenancePlans
      state={await getMaintenancePlans()}
      canManage={can(permissions, "maintenance.manage")}
    />
  );
}

export default function MaintenancePage() {
  const t = useExtracted("maintenance");

  return (
    <>
      <PageHeader
        title={t("Maintenance")}
        description={t(
          "Preventive plans by time or meter, and the work orders they open.",
        )}
      />
      <Suspense fallback={<MaintenancePlansSkeleton />}>
        <PermissionGate permission="maintenance.read">
          <Plans />
        </PermissionGate>
      </Suspense>
    </>
  );
}
