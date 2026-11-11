import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CollectionList,
  CollectionListSkeleton,
} from "@/features/collections/components/collection-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function CollectionsPage() {
  const t = useExtracted("collections");

  return (
    <>
      <PageHeader
        title={t("Collections")}
        description={t(
          "Named lists of customers, personal or shared with the organization.",
        )}
      />
      <Suspense fallback={<CollectionListSkeleton />}>
        <PermissionGate permission="collections.read">
          <CollectionList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
