import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TillsSectionSkeleton,
  TillsSection,
} from "@/features/tills/components/tills-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function TillsPage() {
  const t = useExtracted("tills");

  return (
    <>
      <PageHeader
        title={t("Tills")}
        description={t(
          "Cash drawer shifts with their expected cash and status.",
        )}
      />
      <Suspense fallback={<TillsSectionSkeleton />}>
        <PermissionGate permission="tills.read">
          <TillsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
