import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DocumentList,
  DocumentListSkeleton,
} from "@/features/documents/components/document-list";
import {
  DocumentsOverview,
  DocumentsOverviewSkeleton,
} from "@/features/documents/components/documents-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function DocumentsPage() {
  const t = useExtracted("documents");

  return (
    <>
      <PageHeader
        title={t("Documents")}
        description={t("Shared notes the team writes together.")}
      />
      <Suspense fallback={<DocumentsOverviewSkeleton />}>
        <PermissionGate permission="documents.read">
          <DocumentsOverview />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<DocumentListSkeleton />}>
        <PermissionGate permission="documents.read">
          <DocumentList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
