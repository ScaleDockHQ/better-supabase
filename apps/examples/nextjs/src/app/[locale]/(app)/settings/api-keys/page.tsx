import { Suspense } from "react";

import {
  ApiKeysSection,
  ApiKeysSectionSkeleton,
} from "@/features/api-keys/components/api-keys-section";
import {
  ServicePrincipalsTable,
  ServicePrincipalsTableSkeleton,
} from "@/features/service-principals/components/service-principals-table";

export default function ApiKeysSettingsPage() {
  return (
    <>
      <Suspense fallback={<ApiKeysSectionSkeleton />}>
        <ApiKeysSection />
      </Suspense>
      <Suspense fallback={<ServicePrincipalsTableSkeleton />}>
        <ServicePrincipalsTable />
      </Suspense>
    </>
  );
}
