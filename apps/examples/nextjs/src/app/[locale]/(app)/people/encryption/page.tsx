import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  EncryptedFields,
  EncryptedFieldsSkeleton,
} from "@/features/encryption/components/encrypted-fields";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function EncryptionPage() {
  const t = useExtracted("encryption");

  return (
    <>
      <PageHeader
        title={t("Field encryption")}
        description={t(
          "Which fields are encrypted at rest, and the key that seals them.",
        )}
      />
      <Suspense fallback={<EncryptedFieldsSkeleton />}>
        <PermissionGate permission="custom_fields.read">
          <EncryptedFields />
        </PermissionGate>
      </Suspense>
    </>
  );
}
