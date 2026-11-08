import { Suspense } from "react";

import {
  AiProviderSectionSkeleton,
  AiProviderSection,
} from "@/features/ai-providers/components/ai-provider-section";

export default function AiProvidersSettingsPage() {
  return (
    <Suspense fallback={<AiProviderSectionSkeleton />}>
      <AiProviderSection />
    </Suspense>
  );
}
