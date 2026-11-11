import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { PermissionGate } from "@/features/user/components/permission-gate";
import {
  ClaimList,
  ClaimListSkeleton,
} from "@/features/warranty/components/claim-list";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function WarrantyPage() {
  const t = useExtracted("warranty");

  return (
    <>
      <PageHeader
        title={t("Warranty claims")}
        description={t("Claims on your assets, from draft to decision.")}
      />
      <Suspense fallback={<ClaimListSkeleton />}>
        <PermissionGate permission="warranty.read">
          <ClaimList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
