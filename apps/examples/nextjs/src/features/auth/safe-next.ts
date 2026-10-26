import type { Route } from "next";

import { isLocalizedRoute } from "@/i18n/navigation";

/**
 * The `?next=` path the proxy put on the sign-in URL, or `fallback`. Only
 * same-origin paths pass, so the parameter can't send anyone elsewhere. Read at
 * submit time, so the page needs no `useSearchParams` boundary.
 */
export function safeNext<F extends string>(fallback: F): Route | F {
  const next = new URLSearchParams(window.location.search).get("next");

  return next !== null && isLocalizedRoute(next) ? next : fallback;
}
