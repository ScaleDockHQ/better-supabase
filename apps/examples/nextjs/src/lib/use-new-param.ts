"use client";

import { useSearchParams } from "next/navigation";

/**
 * True when the URL carries `?new=1`, the link the command center uses to land
 * on a page with its create dialog already open. Render the caller inside
 * `<Suspense>`.
 */
export function useNewParam(): boolean {
  return useSearchParams().get("new") === "1";
}
