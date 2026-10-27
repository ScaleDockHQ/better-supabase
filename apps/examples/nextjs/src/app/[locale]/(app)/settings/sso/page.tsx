import { Suspense } from "react";

import {
  SsoSettings,
  SsoSettingsSkeleton,
} from "@/features/sso/components/sso-settings";

export default function SsoSettingsPage() {
  return (
    <Suspense fallback={<SsoSettingsSkeleton />}>
      <SsoSettings />
    </Suspense>
  );
}
