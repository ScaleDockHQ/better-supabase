import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { Rfqs } from "@/features/rfqs/components/rfqs";
import { getRfqs } from "@/features/rfqs/rfqs-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function RfqsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Rfqs state={await getRfqs()} canWrite={can(permissions, "rfqs.write")} />
  );
}

export function RfqsSectionSkeleton() {
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
