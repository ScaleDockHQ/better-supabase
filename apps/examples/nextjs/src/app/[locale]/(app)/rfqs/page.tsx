import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RfqsSkeleton } from "@/features/rfqs/components/rfqs";
import { RfqsSection } from "@/features/rfqs/components/rfqs-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function RfqsPage() {
  const t = useExtracted("rfqs");

  return (
    <>
      <PageHeader
        title={t("Requests for quotation")}
        description={t(
          "Requests sent to suppliers, their quotes and the award.",
        )}
      />
      <Suspense fallback={<RfqsSkeleton />}>
        <PermissionGate permission="rfqs.read">
          <RfqsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
