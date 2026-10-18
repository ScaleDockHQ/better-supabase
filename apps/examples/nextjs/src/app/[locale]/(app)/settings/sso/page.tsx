import { Suspense } from "react";

import {
  SsoSettings,
  SsoSettingsSkeleton,
} from "@/features/sso/components/sso-settings";

export const instant = true;

export default function SsoSettingsPage() {
  return (
    <Suspense fallback={<SsoSettingsSkeleton />}>
      <SsoSettings />
    </Suspense>
  );
}
