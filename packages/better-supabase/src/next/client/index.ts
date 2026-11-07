"use client";

import { useRouter } from "next/navigation.js";
import { useCallback, useEffect, useRef, useState } from "react";

import type { SessionStatusBody } from "../../server/session-status.ts";
import type {
  SessionWatchEvent,
  SessionWatchOptions,
} from "./session-watch.ts";

import { watchSession } from "./session-watch.ts";

export { watchSession } from "./session-watch.ts";

export type {
  SessionChangeReason,
  SessionWatchEvent,
  SessionWatcher,
  SessionWatchOptions,
} from "./session-watch.ts";

export type {
  SessionStatusBody,
  SessionWatchStatus,
} from "../../server/session-status.ts";

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
 * After a session change, expire the server cache (`changed`), navigate, then
 * refresh the client router. `refresh()` in a Server Action leaves prefetched
 * private App Shells, so `router.push` alone shows the old session. Pass a
 * next-intl (or other) router when `push` must keep the locale prefix.
 *
 * ```ts
 * const switched = useSessionChange(sessionChanged, router, {
 *   refreshToken: useSupabase(),
 * });
 * await switched("/dashboard");
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

        if (error) {
          throw error;
        }
      }

      await changed();

      if (to !== undefined) {
        used.push(to);
      }

      used.refresh();
    },
    [changed, used, refresher],
  );
}

export interface UseSessionWatchOptions extends SessionWatchOptions {
  /**
   * Replaces the default reaction. By default an ended, banned or signed-out
   * session loads `redirect` (or the current page, which the proxy then sends
   * to sign-in) as a full document load, and a claims change refreshes the
   * router so Server Components render with the new claims.
   */
  readonly onChange?: (event: SessionWatchEvent) => void;
  /** Where an ended session goes. Defaults to reloading the current page. */
  readonly redirect?: string;
  /** The router a claims change refreshes. Defaults to Next.js's. */
  readonly router?: Pick<SessionChangeRouter, "refresh">;
  /** Pauses the watch, e.g. on pages without a session. */
  readonly enabled?: boolean;
}

/**
 * Watches the session of an app that keeps it in httpOnly cookies, without a
 * browser Supabase client: it asks `sessionStatusRoute` on focus, when the tab
 * becomes visible and on an interval, and reacts when Auth ended the session,
 * banned the user, the user signed out, or the claims or support target
 * changed. Other tabs of the app hear each change through a `BroadcastChannel`.
 * Returns the last answer.
 *
 * ```tsx
 * useSessionWatch({ url: "/api/session-status", redirect: "/sign-in" });
 * ```
 */
export function useSessionWatch(
  options: UseSessionWatchOptions = {},
): SessionStatusBody | undefined {
  const nextRouter = useRouter();
  const [last, setLast] = useState<SessionStatusBody | undefined>(undefined);
  const latest = useRef({ options, router: options.router ?? nextRouter });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the watch reads the newest callbacks without restarting.
  latest.current = { options, router: options.router ?? nextRouter };
  const { url, intervalMs, channel, fingerprint } = options;
  const enabled = options.enabled ?? true;

  useEffect(() => {
    if (!enabled) {
      return;
    }

    const watcher = watchSession(
      (event) => {
        const current = latest.current;

        if (current.options.onChange) {
          current.options.onChange(event);

          return;
        }

        if (event.reason === "claims_changed") {
          current.router.refresh();

          return;
        }

        window.location.assign(
          current.options.redirect ?? window.location.href,
        );
      },
      {
        ...(url === undefined ? {} : { url }),
        ...(intervalMs === undefined ? {} : { intervalMs }),
        ...(channel === undefined ? {} : { channel }),
        ...(fingerprint === undefined ? {} : { fingerprint }),
        ...(latest.current.options.fetch
          ? { fetch: latest.current.options.fetch }
          : {}),
        onStatus: setLast,
      },
    );

    return () => {
      watcher.stop();
    };
  }, [enabled, url, intervalMs, channel, fingerprint]);

  return last;
}
