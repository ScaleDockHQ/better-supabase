"use client";

import { useLocale } from "next-intl";

/** The accept link for an invitation token, on this origin and locale. */
export function useInviteLink(): (token: string) => string {
  const locale = useLocale();
  return (token) =>
    `${window.location.origin}/${locale}/invite/${encodeURIComponent(token)}`;
}
