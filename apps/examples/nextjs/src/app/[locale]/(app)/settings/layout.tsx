import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function SettingsLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

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
        "sso",
        "teams",
        "webhooks",
      ])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
