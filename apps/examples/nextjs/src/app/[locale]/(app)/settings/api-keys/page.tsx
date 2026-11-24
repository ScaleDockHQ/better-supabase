import { Suspense } from "react";

import {
  ApiKeysKpiBand,
  ApiKeysKpiBandSkeleton,
} from "@/features/api-keys/components/api-keys-kpi-band";
import {
  ApiKeysSectionSkeleton,
  ApiKeysSection,
} from "@/features/api-keys/components/api-keys-section";
import {
  ServicePrincipalsTable,
  ServicePrincipalsTableSkeleton,
} from "@/features/service-principals/components/service-principals-table";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ApiKeysSettingsPage() {
  return (
    <>
      <Suspense fallback={<ApiKeysKpiBandSkeleton />}>
        <ApiKeysKpiBand />
      </Suspense>
      <Suspense fallback={<ApiKeysSectionSkeleton />}>
        <ApiKeysSection />
      </Suspense>
      <Suspense fallback={<ServicePrincipalsTableSkeleton />}>
        <ServicePrincipalsTable />
      </Suspense>
    </>
  );
}
