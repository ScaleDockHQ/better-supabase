import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SamplesSectionSkeleton,
  SamplesSection,
} from "@/features/lims/components/samples-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function LimsPage() {
  const t = useExtracted("lims");

  return (
    <>
      <PageHeader
        title={t("Laboratory")}
        description={t(
          "Samples, their results and whether they may be released.",
        )}
      />
      <Suspense fallback={<SamplesSectionSkeleton />}>
        <PermissionGate permission="lims.read">
          <SamplesSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
