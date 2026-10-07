import { type AbstractIntlMessages, hasLocale } from "next-intl";
import { getRequestConfig } from "next-intl/server";
import { notFound } from "next/navigation";
import * as rootParams from "next/root-params";

import { routing } from "./routing";

const catalogs = {
  en: () => import("../../messages/en.po"),
  nl: () => import("../../messages/nl.po"),
} satisfies Record<
  (typeof routing.locales)[number],
  () => Promise<{ default: AbstractIntlMessages }>
>;

/**
 * Pages and layouts read the locale from the `[locale]` root param. Server
 * Actions and Route Handlers have no root params, so they pass `locale` to
 * `getExtracted({ locale })` themselves.
 */
export default getRequestConfig(async ({ locale }) => {
  const requested = locale ?? (await rootParams.locale());
  if (!hasLocale(routing.locales, requested)) notFound();
  return {
    locale: requested,
    // A fixed zone, so server and browser format dates the same way.
    timeZone: "UTC",
    messages: (await catalogs[requested]()).default,
  };
});
