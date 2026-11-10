import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { pick } from "@/i18n/namespaces";

export default function SendLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, ["drive", "errors", "offline"])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
