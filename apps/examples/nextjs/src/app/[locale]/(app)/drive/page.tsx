import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DocumentRegister,
  DocumentRegisterSkeleton,
} from "@/features/drive/components/document-register";
import {
  DriveExplorer,
  DriveExplorerSkeleton,
} from "@/features/drive/components/drive-explorer";
import { getDocumentRegister } from "@/features/drive/drive-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";

const ROOT = Promise.resolve(null);

async function Register() {
  return <DocumentRegister state={await getDocumentRegister()} />;
}

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
      <Suspense fallback={<DocumentRegisterSkeleton />}>
        <PermissionGate permission="drive.read">
          <Register />
        </PermissionGate>
      </Suspense>
    </>
  );
}
