import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { ConnectInstallation } from "@/features/marketplace/components/connect-installation";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function MarketplaceSettingsPage() {
  const t = useExtracted("marketplace");

  return (
    <>
      <PageHeader
        title={t("Vercel Marketplace")}
        description={t(
          "Installations of this app from the Vercel Marketplace, with the resources Vercel provisioned for each.",
        )}
      />
      <Suspense fallback={null}>
        <PermissionGate permission="settings.manage">
          <ConnectInstallation />
        </PermissionGate>
      </Suspense>
    </>
  );
}
