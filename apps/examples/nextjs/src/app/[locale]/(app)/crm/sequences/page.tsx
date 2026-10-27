import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SequenceBuilder,
  SequenceBuilderSkeleton,
} from "@/features/sequences/components/sequence-builder";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function SequencesPage() {
  const t = useExtracted("sequences");

  return (
    <>
      <PageHeader
        title={t("Sequences")}
        description={t(
          "Email, wait and task steps that run for each enrolled contact until they reply.",
        )}
      />
      <Suspense fallback={<SequenceBuilderSkeleton />}>
        <PermissionGate permission="sequences.read">
          <SequenceBuilder />
        </PermissionGate>
      </Suspense>
    </>
  );
}
