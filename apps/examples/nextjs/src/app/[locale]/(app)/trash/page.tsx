import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TrashBin,
  TrashBinSkeleton,
} from "@/features/trash/components/trash-bin";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function TrashPage() {
  const t = useExtracted("trash");

  return (
    <>
      <PageHeader
        title={t("Trash")}
        description={t(
          "Deleted items stay here until they are restored or removed for good.",
        )}
      />
      <Suspense fallback={<TrashBinSkeleton />}>
        <PermissionGate permission="trash.read">
          <TrashBin />
        </PermissionGate>
      </Suspense>
    </>
  );
}
