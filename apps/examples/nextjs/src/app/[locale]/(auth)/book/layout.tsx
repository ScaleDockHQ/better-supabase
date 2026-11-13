import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { ErrorMessages } from "@/components/error-messages";
import { pick } from "@/i18n/namespaces";

export default function BookLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, ["bookings", "errors", "offline"])}
    >
      <ErrorMessages>{children}</ErrorMessages>
    </NextIntlClientProvider>
  );
}
