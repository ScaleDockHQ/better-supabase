import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import {
  PickListGrid,
  PickListGridSkeleton,
} from "@/features/warehouse/components/pick-list-grid";
import { getPickLists } from "@/features/warehouse/warehouse-queries";

async function PickLists() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <PickListGrid
      state={await getPickLists()}
      canPick={can(permissions, "warehouse.pick")}
    />
  );
}

export default function WarehousePage() {
  const t = useExtracted("warehouse");

  return (
    <>
      <PageHeader
        title={t("Warehouse")}
        description={t(
          "Pick lists made from stock allocations, with the stock to take from each bin.",
        )}
      />
      <Suspense fallback={<PickListGridSkeleton />}>
        <PermissionGate permission="warehouse.pick">
          <PickLists />
        </PermissionGate>
      </Suspense>
    </>
  );
}
