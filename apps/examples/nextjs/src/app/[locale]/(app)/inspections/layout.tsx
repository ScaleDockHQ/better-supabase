import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function InspectionsLayout({
  children,
}: {
  children: ReactNode;
}) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        "crm",
        "customers",
        "recordDetail",
        "records",
        "sales",
        "subjects",
        "inspections",
      ])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
