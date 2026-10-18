import { Suspense } from "react";

import { AiProviderSection } from "@/features/ai-providers/components/ai-provider-section";
import { AiProviderSettingsSkeleton } from "@/features/ai-providers/components/ai-provider-settings";

export const instant = true;

export default function AiProvidersSettingsPage() {
  return (
    <div data-recipe="ai-provider-settings">
      <Suspense fallback={<AiProviderSettingsSkeleton />}>
        <AiProviderSection />
      </Suspense>
    </div>
  );
}
