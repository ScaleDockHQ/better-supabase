import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { PickListGrid } from "@/features/warehouse/components/pick-list-grid";
import { getPickLists } from "@/features/warehouse/warehouse-queries";

export async function PickListGridSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <PickListGrid
      state={await getPickLists()}
      canPick={can(permissions, "warehouse.pick")}
    />
  );
}

export function PickListGridSectionSkeleton() {
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
