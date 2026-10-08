"use client";

import { useRouter } from "next/navigation.js";
import { useCallback } from "react";

/** The `push` and `refresh` `useSessionChange` needs; next-intl's router fits. */
export interface SessionChangeRouter {
  push(href: string): void;
  refresh(): void;
}

/** The part of a supabase-js client `refreshToken` calls, e.g. `useSupabase()`. */
export interface TokenRefresher {
  readonly auth: {
    refreshSession(): Promise<{ readonly error: Error | null }>;
  };
}

export interface SessionChangeOptions {
  /**
   * Refresh the browser's access token first, so the server reads the new
   * claims (an organization switch, a new membership) from the cookie.
   */
  readonly refreshToken?: TokenRefresher;
}

/**
 * After a session change, expire the server cache (`changed`), navigate,
 * then refresh the client router. `refresh()` in a Server Action leaves
 * prefetched private App Shells, so `router.push` alone shows the old
 * session. Pass a next-intl (or other) router when `push` must keep the
 * locale prefix.
 *
 * ```ts
 * const switched = useSessionChange(sessionChanged, router, { refreshToken: useSupabase() });
 * await switched('/dashboard');
 * ```
 */
export function useSessionChange(
  changed: () => Promise<void>,
  router?: SessionChangeRouter,
  options: SessionChangeOptions = {},
): (to?: string) => Promise<void> {
  const nextRouter = useRouter();
  const used = router ?? nextRouter;
  const refresher = options.refreshToken;
  return useCallback(
    async (to?: string): Promise<void> => {
      if (refresher) {
        const { error } = await refresher.auth.refreshSession();
        if (error) throw error;
      }
      await changed();
      if (to !== undefined) used.push(to);
      used.refresh();
    },
    [changed, used, refresher],
  );
}
