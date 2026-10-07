/** The part of React Native's `AppState` that `autoRefreshOnForeground` uses. */
export interface AppStateLike {
  readonly currentState: string;
  addEventListener(
    type: "change",
    listener: (state: string) => void,
  ): { remove(): void };
}

/** The part of a supabase-js client that `autoRefreshOnForeground` uses. */
export interface AutoRefreshClient {
  readonly auth: {
    startAutoRefresh(): Promise<void>;
    stopAutoRefresh(): Promise<void>;
  };
}

/**
 * Refreshes the Supabase session only while the app is in the foreground,
 * as supabase-js requires on React Native. Returns a function that removes
 * the listener and stops refreshing.
 *
 * ```ts
 * import { AppState } from 'react-native';
 * autoRefreshOnForeground(supabase, AppState);
 * ```
 */
export function autoRefreshOnForeground(
  supabase: AutoRefreshClient,
  appState: AppStateLike,
): () => void {
  const apply = (state: string): void => {
    if (state === "active") void supabase.auth.startAutoRefresh();
    else void supabase.auth.stopAutoRefresh();
  };
  if (appState.currentState === "active") apply("active");
  const subscription = appState.addEventListener("change", apply);
  return () => {
    subscription.remove();
    void supabase.auth.stopAutoRefresh();
  };
}
