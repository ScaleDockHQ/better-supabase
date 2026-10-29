import type { AuthzVersionSource } from "../../core/authz-topic.ts";
import type {
  AuthzPresence,
  AuthzRefreshClient,
  AuthzTopicOptions,
  LiveVersionSource,
} from "../authz-refresh.ts";
import type { AppStateLike } from "./auto-refresh.ts";

import { authzVersionOf } from "../../auth/snapshot.ts";
import { decodeJwtPayload } from "../../core/base64.ts";
import {
  errorOf,
  realtimeVersionSource,
  runAuthzRefresh,
} from "../authz-refresh.ts";

/** The part of a React Native supabase-js client the refresh uses. */
export interface NativeAuthzRefreshClient extends AuthzRefreshClient {
  readonly auth: AuthzRefreshClient["auth"] & {
    getSession(): Promise<{
      readonly data: {
        readonly session: { readonly access_token: string } | null;
      };
    }>;
  };
}

/** `syncWithAuth(...)` from `better-supabase/powersync`. */
export interface PowerSyncReconnect {
  readonly reconnect: () => Promise<void>;
}

export interface NativeAuthzRefreshOptions extends AuthzTopicOptions {
  readonly client: NativeAuthzRefreshClient;
  readonly userId: string;
  /** React Native's `AppState`. */
  readonly appState: AppStateLike;
  /** Runs after the token refresh, such as refetching the screen's queries. */
  readonly onChange?: () => unknown;
  /**
   * The value `syncWithAuth` returned. After a refresh it reconnects, so the
   * sync service reads the new token and drops rows the user lost.
   */
  readonly powersync?: PowerSyncReconnect;
  /** Where versions come from. Defaults to the user's `authz:<uid>` topic. */
  readonly source?: AuthzVersionSource;
  readonly onError?: (error: Error) => void;
}

const isActive = (state: string): boolean => state === "active";

/**
 * Follows the app's foreground: subscribes while active and drops the channel
 * in the background, where the OS closes the socket anyway. Each join reads the
 * live version, so a change made while the app was away arrives on return.
 */
function foregroundSource(
  inner: LiveVersionSource,
  appState: AppStateLike,
): LiveVersionSource {
  return {
    current: () => inner.current(),
    subscribe(listener, onLive) {
      let stop = isActive(appState.currentState)
        ? inner.subscribe(listener, onLive)
        : undefined;

      const change = appState.addEventListener("change", (state) => {
        if (isActive(state)) {
          stop ??= inner.subscribe(listener, onLive);
        } else {
          stop?.();
          stop = undefined;
        }
      });

      return () => {
        change.remove();
        stop?.();
      };
    },
  };
}

function appPresence(appState: AppStateLike, catchUp: boolean): AuthzPresence {
  return {
    active: () => isActive(appState.currentState),
    onActive(listener) {
      if (!catchUp) {
        return () => undefined;
      }

      const change = appState.addEventListener("change", (state) => {
        if (isActive(state)) {
          listener();
        }
      });

      return () => {
        change.remove();
      };
    },
  };
}

/**
 * Refreshes the token when the database bumps the user's authorization version,
 * on iOS and Android. It listens on `authz:<uid>` while the app is in the
 * foreground, reads the live version on each join and on return from the
 * background, and refreshes only when the live version is ahead of the token's.
 * With `powersync`, it reconnects the sync stream afterwards. Returns the
 * cleanup.
 *
 * ```ts
 * import { AppState } from "react-native";
 * startNativeAuthzRefresh({
 *   client: supabase,
 *   userId,
 *   appState: AppState,
 *   powersync: sync,
 * });
 * ```
 */
export function startNativeAuthzRefresh(
  options: NativeAuthzRefreshOptions,
): () => void {
  const report = (cause: unknown): void => {
    options.onError?.(errorOf(cause));
  };

  const source =
    options.source ??
    foregroundSource(
      realtimeVersionSource(options.client, options.userId, {
        ...(options.topic ? { topic: options.topic } : {}),
        ...(options.event ? { event: options.event } : {}),
        onError: report,
      }),
      options.appState,
    );

  const refresh = runAuthzRefresh({
    source,
    presence: appPresence(options.appState, options.source !== undefined),
    tokenVersion: async () => {
      const { data } = await options.client.auth.getSession();

      const claims = data.session
        ? decodeJwtPayload(data.session.access_token)
        : undefined;

      return claims ? authzVersionOf(claims) : null;
    },
    refresh: () => options.client.auth.refreshSession(),
    onRefreshed: async () => {
      await options.onChange?.();
      await options.powersync?.reconnect();
    },
    onError: report,
  });

  return refresh.stop;
}
