import { Suspense } from "react";

import {
  PrivacySettings,
  PrivacySettingsSkeleton,
} from "@/features/privacy/components/privacy-settings";

export const instant = true;

export default function PrivacySettingsPage() {
  return (
    <Suspense fallback={<PrivacySettingsSkeleton />}>
      <PrivacySettings />
    </Suspense>
  );
}
