import { Suspense } from "react";

import {
  ConnectorList,
  ConnectorListSkeleton,
} from "@/features/integrations/components/connector-list";
import {
  IntegrationSectionSkeleton,
  IntegrationSection,
} from "@/features/integrations/components/integration-section";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function IntegrationsSettingsPage() {
  return (
    <div className="flex flex-col gap-6">
      <Suspense fallback={<IntegrationSectionSkeleton />}>
        <IntegrationSection />
      </Suspense>
      <Suspense fallback={<ConnectorListSkeleton />}>
        <ConnectorList />
      </Suspense>
    </div>
  );
}
