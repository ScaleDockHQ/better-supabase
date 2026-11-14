import { Suspense } from "react";

import {
  PrivacySettings,
  PrivacySettingsSkeleton,
} from "@/features/privacy/components/privacy-settings";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function PrivacySettingsPage() {
  return (
    <Suspense fallback={<PrivacySettingsSkeleton />}>
      <PrivacySettings />
    </Suspense>
  );
}
