import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

const NO_NAMESPACES: readonly string[] = [];

/**
 * The messages a finance list or record page reads on the client, for the
 * layout of each route that holds one.
 */
export function FinanceMessages({
  children,
  also = NO_NAMESPACES,
}: {
  children: ReactNode;
  /** Namespaces the route's own client components read besides the finance ones. */
  also?: readonly string[];
}) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        ...also,
        "finance",
        "recordDetail",
        "recordList",
      ])}
    >
      {children}
    </NextIntlClientProvider>
  );
}
