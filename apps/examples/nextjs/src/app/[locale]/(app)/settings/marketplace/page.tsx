import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MarketplaceOverview,
  MarketplaceOverviewSkeleton,
} from "@/features/marketplace/components/marketplace-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function MarketplaceSettingsPage() {
  const t = useExtracted("marketplace");

  return (
    <>
      <PageHeader
        title={t("Vercel Marketplace")}
        description={t(
          "The installation of this app from the Vercel Marketplace that is linked to this organization, with the resources Vercel provisioned.",
        )}
      />
      <Suspense fallback={<MarketplaceOverviewSkeleton />}>
        <PermissionGate permission="settings.manage">
          <MarketplaceOverview />
        </PermissionGate>
      </Suspense>
    </>
  );
}
