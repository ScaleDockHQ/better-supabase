import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  ResourceDetail,
  ResourceDetailSkeleton,
} from "@/features/marketplace/components/resource-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A navigation here shows the back link at once; the resource streams in.
export const instant = true;

export default function MarketplaceResourcePage({
  params,
}: PageProps<"/[locale]/settings/marketplace/[resource]">) {
  const t = useExtracted("marketplace");

  return (
    <>
      <AdminBackLink href="/settings/marketplace">
        {t("All resources")}
      </AdminBackLink>
      <Suspense fallback={<ResourceDetailSkeleton />}>
        <PermissionGate permission="settings.manage">
          {params.then(({ resource }) => (
            <ResourceDetail externalId={decodeURIComponent(resource)} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
