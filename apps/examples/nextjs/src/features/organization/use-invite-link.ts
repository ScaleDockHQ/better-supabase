"use client";

import { useLocale } from "next-intl";

import { localizedPath } from "@/i18n/routing";

/** The accept link for an invitation token, on this origin and locale. */
export function useInviteLink(): (token: string) => string {
  const locale = useLocale();

  return (token) =>
    `${window.location.origin}${localizedPath(locale, `/invite/${encodeURIComponent(token)}`)}`;
}
