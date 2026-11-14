import { Suspense } from "react";

import { PushOptIn } from "@/features/push/components/push-opt-in";
import {
  Preferences,
  PreferencesSkeleton,
} from "@/features/settings/components/preferences";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function PreferencesSettingsPage() {
  return (
    <>
      <Suspense fallback={<PreferencesSkeleton />}>
        <Preferences />
      </Suspense>
      <PushOptIn />
    </>
  );
}
