import { useExtracted } from "next-intl";
import { Suspense } from "react";

import {
  GuestPortal,
  GuestPortalSkeleton,
} from "@/features/portal/components/guest-portal";

// The heading and the skeleton paint at once; the grants stream in.
export const instant = true;

export default function PortalPage() {
  const t = useExtracted("portal");

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("Shared with you")}
      </h1>
      <Suspense fallback={<GuestPortalSkeleton />}>
        <GuestPortal />
      </Suspense>
    </div>
  );
}
