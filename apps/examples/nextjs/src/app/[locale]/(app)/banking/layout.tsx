import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function BankingLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        "finance",
        "recordDetail",
        "recordList", "banking",
      ])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
