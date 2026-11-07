import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { Tills } from "@/features/tills/components/tills";
import { getTillSessions } from "@/features/tills/tills-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function TillsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Tills
      state={await getTillSessions()}
      canManage={can(permissions, "tills.manage")}
    />
  );
}

export function TillsSectionSkeleton() {
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
