"use client";

import { useRouter } from "next/navigation.js";
import { useCallback } from "react";

/** The `push` and `refresh` `useSessionChange` needs; next-intl's router fits. */
export interface SessionChangeRouter {
  push(href: string): void;
  refresh(): void;
}

/**
 * After a session change, expire the server cache (`changed`), navigate,
 * then refresh the client router. `refresh()` in a Server Action leaves
 * prefetched private App Shells, so `router.push` alone shows the old
 * session. Pass a next-intl (or other) router when `push` must keep the
 * locale prefix.
 */
export function useSessionChange(
  changed: () => Promise<void>,
  router?: SessionChangeRouter,
): (to?: string) => Promise<void> {
  const nextRouter = useRouter();
  const used = router ?? nextRouter;
  return useCallback(
    async (to?: string): Promise<void> => {
      await changed();
      if (to !== undefined) used.push(to);
      used.refresh();
    },
    [changed, used],
  );
}
