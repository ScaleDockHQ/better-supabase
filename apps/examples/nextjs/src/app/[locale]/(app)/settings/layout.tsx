import type { ReactNode } from "react";

import { NextIntlClientProvider, useExtracted, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function SettingsLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();
  const t = useExtracted("settings");

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        "accessRequests",
        "aiProviders",
        "apiKeys",
        "audit",
        "billing",
        "adminLists",
        "custom-fields",
        "credits",
        "customers",
        "domains",
        "flagAdmin",
        "incomingWebhooks",
        "integrations",
        "jobs",
        "numbering",
        "oauthApps",
        "optionSets",
        "members",
        "privacy",
        "push",
        "recordDetail",
        "recordList",
        "roles",
        "searchSettings",
        "security",
        "securityEvents",
        "servicePrincipals",
        "sessions",
        "signingKeys",
        "support",
        "marketplace",
        "identities",
        "sso",
        "teams",
        "webhooks",
      ])}
    >
      <h1 className="sr-only">{t("Settings")}</h1>
      {children}
    </NextIntlClientProvider>
  );
}
