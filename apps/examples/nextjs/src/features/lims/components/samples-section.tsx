import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { Samples } from "@/features/lims/components/samples";
import { getSamples } from "@/features/lims/lims-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function SamplesSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Samples
      state={await getSamples()}
      canWrite={can(permissions, "lims.write")}
    />
  );
}

export function SamplesSectionSkeleton() {
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
