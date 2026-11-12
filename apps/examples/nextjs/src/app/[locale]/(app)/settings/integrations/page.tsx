import { Suspense } from "react";

import {
  ConnectorList,
  ConnectorListSkeleton,
} from "@/features/integrations/components/connector-list";
import {
  IntegrationSectionSkeleton,
  IntegrationSection,
} from "@/features/integrations/components/integration-section";

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
