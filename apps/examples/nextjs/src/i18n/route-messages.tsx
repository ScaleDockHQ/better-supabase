import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

/**
 * Hands the client islands below it the message namespaces they read, not the
 * whole catalog (about 130 KB of RSC on `/login`). A nested provider replaces
 * its parent's messages, so each layout lists every namespace its subtree uses,
 * parents included; `tests/i18n/route-namespaces.test.ts` fails when a client
 * component reads a namespace its nearest provider omits, which would show a
 * raw key.
 */
export function RouteMessages({
  namespaces,
  children,
}: {
  namespaces: readonly string[];
  children: ReactNode;
}) {
  const messages = useMessages();

  const picked = Object.fromEntries(
    namespaces.flatMap((namespace) =>
      namespace in messages ? [[namespace, messages[namespace]]] : [],
    ),
  );

  return (
    <NextIntlClientProvider messages={picked}>
      {children}
    </NextIntlClientProvider>
  );
}
