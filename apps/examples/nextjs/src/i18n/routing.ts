import type { Route } from "next";

import { defineRouting } from "next-intl/routing";

export const routing = defineRouting({
  locales: ["en", "nl"],
  defaultLocale: "en",
  localePrefix: "as-needed",
});

export type Locale = (typeof routing.locales)[number];

/**
 * `href` (a path from the app's root) as the URL a visitor of `locale` opens:
 * the default locale has no prefix, the others do. It matches next-intl's
 * `getPathname` and imports no React, so the proxy and client forms both use
 * it.
 */
export function localizedPath(locale: string, href: string): Route {
  const path =
    locale === routing.defaultLocale
      ? href
      : href === "/"
        ? `/${locale}`
        : `/${locale}${href}`;

  // SAFETY: `href` is a path of the app and `locale` is one of its locales, so the result is a same-origin page path; the typed-routes union can't be built from a runtime locale.
  return path;
}
