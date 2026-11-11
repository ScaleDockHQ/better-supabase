import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getAssets } from "../assets-queries";
import { AssetRecordList } from "./asset-record-list";

/** Render inside `<Suspense>`; the fallback is `AssetListSkeleton`. */
export async function AssetList() {
  const [page, permissions, t] = await Promise.all([
    getAssets(),
    getPermissions(),
    getExtracted("assets"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its assets.")}
      </p>
    );
  }

  return (
    <AssetRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canManage={can(permissions, "assets.manage")}
    />
  );
}

export function AssetListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
