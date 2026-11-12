import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function WarehouseLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        "warehouse",
        "recordDetail",
        "recordList",
        "sales",
      ])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
