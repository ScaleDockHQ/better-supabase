import { Suspense } from "react";

import { PushOptIn } from "@/features/push/components/push-opt-in";
import {
  Preferences,
  PreferencesSkeleton,
} from "@/features/settings/components/preferences";

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
