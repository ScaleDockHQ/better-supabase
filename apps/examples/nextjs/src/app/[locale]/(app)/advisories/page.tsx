import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AdvisoryList,
  AdvisoryListSkeleton,
  ProductList,
  ProductListSkeleton,
  VulnerabilityList,
  VulnerabilityListSkeleton,
} from "@/features/advisories/components/advisory-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function AdvisoriesPage() {
  const t = useExtracted("advisories");

  return (
    <>
      <PageHeader
        title={t("Advisories")}
        description={t(
          "Security advisories for the software the organization ships: products, tracked vulnerabilities and the CSAF documents that tell customers what to do.",
        )}
      />
      <Suspense fallback={<AdvisoryListSkeleton />}>
        <PermissionGate permission="advisories.read">
          <AdvisoryList />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<ProductListSkeleton />}>
        <PermissionGate permission="advisories.read">
          <ProductList />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<VulnerabilityListSkeleton />}>
        <PermissionGate permission="advisories.read">
          <VulnerabilityList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
