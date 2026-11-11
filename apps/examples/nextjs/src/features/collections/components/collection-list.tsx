import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getCollections } from "../collections-queries";
import { CollectionRecordList } from "./collection-record-list";

/** Render inside `<Suspense>`; the fallback is `CollectionListSkeleton`. */
export async function CollectionList() {
  const [page, permissions, t] = await Promise.all([
    getCollections(),
    getPermissions(),
    getExtracted("collections"),
  ]);

  if (page === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("Pick an organization to see its collections.")}
      </p>
    );
  }

  return (
    <CollectionRecordList
      initial={{ items: page.items, nextCursor: page.nextCursor }}
      canWrite={can(permissions, "collections.write")}
    />
  );
}

export function CollectionListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
