import { io } from "next/cache";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { Prescriptions } from "@/features/e-prescribing/components/prescriptions";
import { getPrescriptions } from "@/features/e-prescribing/e-prescribing-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

export async function PrescriptionsSection() {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  return (
    <Prescriptions
      state={await getPrescriptions()}
      canSign={can(permissions, "e_prescribing.sign")}
      canCancel={can(permissions, "e_prescribing.write")}
    />
  );
}

export function PrescriptionsSectionSkeleton() {
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
