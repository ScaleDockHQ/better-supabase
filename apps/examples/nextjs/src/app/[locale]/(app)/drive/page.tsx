import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DocumentRegisterSectionSkeleton,
  DocumentRegisterSection,
} from "@/features/drive/components/document-register-section";
import {
  DriveExplorer,
  DriveExplorerSkeleton,
} from "@/features/drive/components/drive-explorer";
import { PermissionGate } from "@/features/user/components/permission-gate";

const ROOT = Promise.resolve(null);

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function DrivePage() {
  const t = useExtracted("drive");

  return (
    <>
      <PageHeader
        title={t("Drive")}
        description={t("Your organization's folders and files.")}
      />
      <Suspense fallback={<DriveExplorerSkeleton />}>
        <PermissionGate permission="drive.read">
          <DriveExplorer folderId={ROOT} />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<DocumentRegisterSectionSkeleton />}>
        <PermissionGate permission="drive.read">
          <DocumentRegisterSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
