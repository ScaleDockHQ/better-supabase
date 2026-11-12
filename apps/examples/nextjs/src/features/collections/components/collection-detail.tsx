import type { ReactNode } from "react";

import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getCollection } from "../collections-queries";
import { CollectionActionsBar } from "./collection-actions-bar";
import { CollectionEntries } from "./collection-entries";
import { CollectionScopeBadge } from "./collection-status";

/** One collection with its entries. */
export async function CollectionDetail({
  id,
}: {
  id: string;
}): Promise<ReactNode> {
  const [collection, permissions, t] = await Promise.all([
    getCollection(id),
    getPermissions(),
    getExtracted("collections"),
  ]);

  if (collection === null) {
    notFound();
  }

  const canWrite = can(permissions, "collections.write");

  return (
    <RecordDetailFrame
      title={collection.name}
      description={collection.description ?? ""}
      status={
        <CollectionScopeBadge
          scope={collection.scope}
          archived={collection.archived}
        />
      }
      actions={
        canWrite ? (
          <CollectionActionsBar
            collectionId={collection.id}
            archived={collection.archived}
          />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Customers")}</CardTitle>
        </CardHeader>
        <CardContent>
          <CollectionEntries
            collectionId={collection.id}
            entries={collection.entries}
            candidates={collection.candidates}
            canWrite={canWrite && !collection.archived}
          />
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function CollectionDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-10 w-72" />
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
