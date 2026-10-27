import { Suspense } from "react";

import { IntegrationSection } from "@/features/integrations/components/integration-section";
import { IntegrationSettingsSkeleton } from "@/features/integrations/components/integration-settings";

export default function IntegrationsSettingsPage() {
  return (
    <Suspense fallback={<IntegrationSettingsSkeleton />}>
      <IntegrationSection />
    </Suspense>
  );
}
