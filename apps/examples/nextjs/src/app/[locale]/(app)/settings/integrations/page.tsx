import { Suspense } from "react";

import {
  IntegrationSectionSkeleton,
  IntegrationSection,
} from "@/features/integrations/components/integration-section";

export default function IntegrationsSettingsPage() {
  return (
    <Suspense fallback={<IntegrationSectionSkeleton />}>
      <IntegrationSection />
    </Suspense>
  );
}
