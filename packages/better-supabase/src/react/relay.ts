"use client";

import { useMemo } from "react";

import type { RelayClientOptions } from "../realtime/relay.ts";
import type { RealtimeClient } from "../realtime/topic.ts";

import { relayRealtimeClient } from "../realtime/relay.ts";
import { useOptionalSupportSession } from "./session.ts";

export interface UseRealtimeRelayOptions extends RelayClientOptions {
  /**
   * `support` (the default): the relay only while a support session runs, as
   * `useSupportSession()` reports it from the nearest `<SessionProvider>`.
   * `always`: for apps that keep sessions in httpOnly cookies.
   */
  readonly when?: "support" | "always";
}

/**
 * A `relayRealtimeClient(url)` while it is needed, else `undefined`. Pass it to
 * `<BetterSupabaseProvider realtime={...}>`, and `useBroadcast`, `usePresence`,
 * `useLiveQuery` and `useLiveCount` join through the server's `realtimeRelay`
 * route, as the viewed user in a support session. The client is created once
 * per `url` and options, so pass a stable `fetch` and `EventSource`.
 *
 * ```tsx
 * const realtime = useRealtimeRelay("/api/realtime");
 * return (
 *   <BetterSupabaseProvider client={bsb} realtime={realtime}>
 *     {children}
 *   </BetterSupabaseProvider>
 * );
 * ```
 */
export function useRealtimeRelay(
  url: string,
  options: UseRealtimeRelayOptions = {},
): RealtimeClient | undefined {
  const support = useOptionalSupportSession();
  const active = options.when === "always" || support !== undefined;
  const { EventSource: source, fetch: send, timeoutMs, maxBackoffMs } = options;

  return useMemo(
    () =>
      active
        ? relayRealtimeClient(url, {
            ...(source === undefined ? {} : { EventSource: source }),
            ...(send === undefined ? {} : { fetch: send }),
            ...(timeoutMs === undefined ? {} : { timeoutMs }),
            ...(maxBackoffMs === undefined ? {} : { maxBackoffMs }),
          })
        : undefined,
    [active, url, source, send, timeoutMs, maxBackoffMs],
  );
}
