import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CareSectionSkeleton,
  ClientList,
} from "@/features/care/components/care-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function CarePage() {
  const t = useExtracted("care");

  return (
    <>
      <PageHeader
        title={t("Clients")}
        description={t(
          "The clients in your care. Open one for their notes, care plan, observations, medication, consents and access log.",
        )}
      />
      <Suspense fallback={<CareSectionSkeleton />}>
        <PermissionGate permission="customers.read">
          <ClientList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
