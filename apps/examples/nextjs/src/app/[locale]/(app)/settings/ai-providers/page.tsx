import { Suspense } from "react";

import {
  AiProviderSectionSkeleton,
  AiProviderSection,
} from "@/features/ai-providers/components/ai-provider-section";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function AiProvidersSettingsPage() {
  return (
    <Suspense fallback={<AiProviderSectionSkeleton />}>
      <AiProviderSection />
    </Suspense>
  );
}
