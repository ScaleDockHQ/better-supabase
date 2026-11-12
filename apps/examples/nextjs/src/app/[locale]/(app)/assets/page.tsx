import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AssetList,
  AssetListSkeleton,
} from "@/features/assets/components/asset-list";
import { CreateAssetDialog } from "@/features/assets/components/create-asset-dialog";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the register stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function AssetsPage() {
  const t = useExtracted("assets");

  return (
    <>
      <PageHeader
        title={t("Asset register")}
        description={t(
          "Equipment, vehicles and units, with who holds them and what they are worth.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="assets.manage">
              <CreateAssetDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<AssetListSkeleton />}>
        <PermissionGate permission="assets.read">
          <AssetList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
