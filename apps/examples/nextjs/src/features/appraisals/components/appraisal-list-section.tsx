import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getAppraisals } from "@/features/appraisals/appraisals-queries";
import { AppraisalList } from "@/features/appraisals/components/appraisal-list";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function AppraisalListSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <AppraisalList
      state={await getAppraisals()}
      canManage={can(permissions, "appraisals.manage")}
    />
  );
}

export function AppraisalListSectionSkeleton() {
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
