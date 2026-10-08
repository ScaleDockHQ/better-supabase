import type { AppStateLike, AutoRefreshClient } from "./auto-refresh.ts";

import { autoRefreshOnForeground } from "./auto-refresh.ts";

/** The part of TanStack Query's `focusManager` that `syncQueryWithApp` uses. */
export interface FocusManagerLike {
  setEventListener(
    setup: (
      setFocused: (focused?: boolean) => void,
    ) => (() => void) | undefined,
  ): void;
}

/** The part of TanStack Query's `onlineManager` that `syncQueryWithApp` uses. */
export interface OnlineManagerLike {
  setEventListener(
    setup: (setOnline: (online: boolean) => void) => (() => void) | undefined,
  ): void;
}

/** The part of `@react-native-community/netinfo` that `syncQueryWithApp` uses. */
export interface NetInfoLike {
  addEventListener(
    listener: (state: {
      readonly isConnected: boolean | null;
      readonly isInternetReachable?: boolean | null;
    }) => void,
  ): () => void;
}

export interface SyncQueryWithAppOptions {
  readonly focusManager: FocusManagerLike;
  readonly appState: AppStateLike;
  /** With `netInfo`, queries pause offline and refetch on reconnect. */
  readonly onlineManager?: OnlineManagerLike;
  readonly netInfo?: NetInfoLike;
  /** Also refresh the session only in the foreground (`autoRefreshOnForeground`). */
  readonly supabase?: AutoRefreshClient;
}

const NOOP = (): undefined => undefined;

/**
 * Wires TanStack Query to the app lifecycle on React Native: queries count
 * as focused while the app is active, and as online while NetInfo reports
 * a connection (an unreachable internet counts as offline). Returns a
 * function that removes every listener.
 *
 * ```ts
 * import { focusManager, onlineManager } from '@tanstack/react-query';
 * import NetInfo from '@react-native-community/netinfo';
 * import { AppState } from 'react-native';
 * syncQueryWithApp({ focusManager, onlineManager, appState: AppState, netInfo: NetInfo, supabase });
 * ```
 */
export function syncQueryWithApp(options: SyncQueryWithAppOptions): () => void {
  const { focusManager, onlineManager, appState, netInfo, supabase } = options;
  focusManager.setEventListener((setFocused) => {
    setFocused(appState.currentState === "active");
    const subscription = appState.addEventListener("change", (state) => {
      setFocused(state === "active");
    });
    return () => {
      subscription.remove();
    };
  });
  if (onlineManager && netInfo) {
    onlineManager.setEventListener((setOnline) =>
      netInfo.addEventListener((state) => {
        setOnline(
          state.isConnected === true && state.isInternetReachable !== false,
        );
      }),
    );
  }
  const stopRefresh = supabase
    ? autoRefreshOnForeground(supabase, appState)
    : undefined;
  return () => {
    focusManager.setEventListener(NOOP);
    if (onlineManager && netInfo) onlineManager.setEventListener(NOOP);
    stopRefresh?.();
  };
}
