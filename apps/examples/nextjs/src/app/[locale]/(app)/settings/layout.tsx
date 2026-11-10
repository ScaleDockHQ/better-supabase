import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SettingsNav,
  SettingsNavSkeleton,
} from "@/features/settings/components/settings-nav";
import { RouteMessages } from "@/i18n/route-messages";

export default function SettingsLayout({
  children,
}: LayoutProps<"/[locale]/settings">) {
  const t = useExtracted("settings");

  return (
    <RouteMessages
      namespaces={[
        "accessRequests",
        "aiProviders",
        "announcements",
        "apiKeys",
        "app",
        "audit",
        "billing",
        "custom-fields",
        "customers",
        "dashboard",
        "errors",
        "inbox",
        "integrations",
        "jobs",
        "members",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "privacy",
        "push",
        "roles",
        "search",
        "security",
        "servicePrincipals",
        "sessions",
        "settings",
        "signingKeys",
        "sso",
        "teams",
        "user",
        "webhooks",
      ]}
    >
      <PageHeader
        title={t("Settings")}
        description={t("Your account and your organization.")}
      />
      <Suspense fallback={<SettingsNavSkeleton />}>
        <SettingsNav />
      </Suspense>
      <div className="max-w-4xl space-y-6">{children}</div>
    </RouteMessages>
  );
}
