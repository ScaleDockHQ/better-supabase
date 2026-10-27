import { Suspense } from "react";

import { AiProviderSection } from "@/features/ai-providers/components/ai-provider-section";
import { AiProviderSettingsSkeleton } from "@/features/ai-providers/components/ai-provider-settings";

export default function AiProvidersSettingsPage() {
  return (
    <Suspense fallback={<AiProviderSettingsSkeleton />}>
      <AiProviderSection />
    </Suspense>
  );
}
