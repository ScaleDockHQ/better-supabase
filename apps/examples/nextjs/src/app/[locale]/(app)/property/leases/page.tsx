import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  LeaseList,
  LeaseListSkeleton,
} from "@/features/leases/components/lease-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function LeasesPage() {
  const t = useExtracted("leases");

  return (
    <>
      <PageHeader
        title={t("Leases")}
        description={t(
          "Rental agreements on your assets, with rent, deposit and balance due.",
        )}
      />
      <Suspense fallback={<LeaseListSkeleton />}>
        <PermissionGate permission="leases.read">
          <LeaseList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
