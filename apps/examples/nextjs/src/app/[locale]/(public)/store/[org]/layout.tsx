import { NextIntlClientProvider, useMessages } from "next-intl";
import { Suspense } from "react";

import {
  StoreNav,
  StoreNavSkeleton,
} from "@/features/store/components/store-nav";
import { pick } from "@/i18n/namespaces";

/**
 * The public store of one organization. The header reads the cart cookie, so it
 * streams behind its own boundary and the page below stays in the static
 * shell.
 */
export default function StoreLayout({
  children,
  params,
}: LayoutProps<"/[locale]/store/[org]">) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider messages={pick(messages, ["store", "offline"])}>
      <div className="flex flex-col gap-6">
        <Suspense fallback={<StoreNavSkeleton />}>
          {params.then(({ org }) => (
            <StoreNav slug={org} />
          ))}
        </Suspense>
        {children}
      </div>
    </NextIntlClientProvider>
  );
}
