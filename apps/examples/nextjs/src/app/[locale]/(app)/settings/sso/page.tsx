import { Suspense } from "react";

import {
  SsoSettings,
  SsoSettingsSkeleton,
} from "@/features/sso/components/sso-settings";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function SsoSettingsPage() {
  return (
    <Suspense fallback={<SsoSettingsSkeleton />}>
      <SsoSettings />
    </Suspense>
  );
}
