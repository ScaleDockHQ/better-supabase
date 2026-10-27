import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DocumentList,
  DocumentListSkeleton,
} from "@/features/documents/components/document-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function DocumentsPage() {
  const t = useExtracted("documents");

  return (
    <>
      <PageHeader
        title={t("Documents")}
        description={t("Shared notes the team writes together.")}
      />
      <Suspense fallback={<DocumentListSkeleton />}>
        <PermissionGate permission="documents.read">
          <DocumentList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
