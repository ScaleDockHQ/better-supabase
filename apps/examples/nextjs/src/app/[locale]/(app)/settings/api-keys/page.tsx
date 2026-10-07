import { Suspense } from "react";

import {
  ApiKeysSection,
  ApiKeysSectionSkeleton,
} from "@/features/api-keys/components/api-keys-section";

export const instant = true;

export default function ApiKeysSettingsPage() {
  return (
    <Suspense fallback={<ApiKeysSectionSkeleton />}>
      <ApiKeysSection />
    </Suspense>
  );
}
