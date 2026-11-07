import { io } from "next/cache";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { PickListGrid } from "@/features/warehouse/components/pick-list-grid";
import { getPickLists } from "@/features/warehouse/warehouse-queries";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function PickListGridSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <PickListGrid
      state={await getPickLists()}
      canPick={can(permissions, "warehouse.pick")}
    />
  );
}
