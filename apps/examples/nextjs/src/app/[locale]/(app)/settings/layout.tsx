import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SettingsNav,
  SettingsNavSkeleton,
} from "@/features/settings/components/settings-nav";

export default function SettingsLayout({
  children,
}: LayoutProps<"/[locale]/settings">) {
  const t = useExtracted("settings");
  return (
    <>
      <PageHeader
        title={t("Settings")}
        description={t("Your account and your organization.")}
      />
      <Suspense fallback={<SettingsNavSkeleton />}>
        <SettingsNav />
      </Suspense>
      <div className="max-w-4xl space-y-6">{children}</div>
    </>
  );
}
