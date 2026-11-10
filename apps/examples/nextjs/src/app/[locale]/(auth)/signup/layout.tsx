import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { pick } from "@/i18n/namespaces";

export default function SignupLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider messages={pick(messages, ["auth", "offline"])}>
      {children}
    </NextIntlClientProvider>
  );
}
