import type {
  AuthzPresence,
  AuthzRefreshClient,
  AuthzTopicOptions,
} from "../client/authz-refresh.ts";
import type { AuthzVersionSource } from "../core/authz-topic.ts";

import {
  errorOf,
  realtimeVersionSource,
  runAuthzRefresh,
} from "../client/authz-refresh.ts";

export type {
  AuthzRefreshChannel,
  AuthzRefreshClient,
} from "../client/authz-refresh.ts";

export interface AuthzRefreshOptions extends AuthzTopicOptions {
  readonly client: AuthzRefreshClient;
  readonly userId: string;
  /**
   * Runs after the token refresh, such as a Server Action and
   * `router.refresh()`.
   */
  readonly onChange: () => unknown;
  /** The `BroadcastChannel` name, or `false` for none. */
  readonly channel: string | false;
  /** Where versions come from. Defaults to the user's `authz:<uid>` topic. */
  readonly source?: AuthzVersionSource;
  /**
   * The version the page's token carries (`session.authzVersion`). A live
   * version at or below it needs no refresh.
   */
  readonly tokenVersion?: () => number | null;
  readonly onError?: (error: Error) => void;
}

interface TabMessage {
  readonly type: "better-supabase:authz";
  readonly userId: string;
  readonly version: number;
}

function isTabMessage(value: unknown): value is TabMessage {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const message: Partial<Record<keyof TabMessage, unknown>> = value;

  return (
    message.type === "better-supabase:authz" &&
    typeof message.userId === "string" &&
    typeof message.version === "number"
  );
}

function documentPresence(): AuthzPresence {
  const doc = "document" in globalThis ? globalThis.document : undefined;
  const active = (): boolean => doc?.visibilityState !== "hidden";

  return {
    active,
    onActive(listener) {
      const onVisible = (): void => {
        if (active()) {
          listener();
        }
      };

      doc?.addEventListener("visibilitychange", onVisible);

      return () => doc?.removeEventListener("visibilitychange", onVisible);
    },
  };
}

/**
 * Listens on the user's `authz:<uid>` topic. A visible tab that hears a new
 * version refreshes the token, runs `onChange` and tells the other tabs, which
 * run only `onChange`: the cookies are shared, so one refresh is enough. A
 * hidden tab waits until it becomes visible, then also reads the live version
 * in case it missed a broadcast. Returns the cleanup.
 */
export function startAuthzRefresh(options: AuthzRefreshOptions): () => void {
  const report = (cause: unknown): void => {
    options.onError?.(errorOf(cause));
  };

  const tabs =
    options.channel !== false && typeof BroadcastChannel === "function"
      ? new BroadcastChannel(options.channel)
      : undefined;

  const source =
    options.source ??
    realtimeVersionSource(options.client, options.userId, {
      ...(options.topic ? { topic: options.topic } : {}),
      ...(options.event ? { event: options.event } : {}),
      onError: report,
    });

  const refresh = runAuthzRefresh({
    source,
    presence: documentPresence(),
    tokenVersion: options.tokenVersion ?? (() => null),
    refresh: () => options.client.auth.refreshSession(),
    onRefreshed: async (version) => {
      await options.onChange();

      const message: TabMessage = {
        type: "better-supabase:authz",
        userId: options.userId,
        version,
      };

      // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (1 finding).
      tabs?.postMessage(message);
    },
    onError: report,
  });

  const onTab = (event: MessageEvent): void => {
    const message: unknown = event.data;

    if (
      !isTabMessage(message) ||
      message.userId !== options.userId ||
      !refresh.handled(message.version)
    ) {
      return;
    }

    Promise.resolve(options.onChange()).catch(report);
  };

  tabs?.addEventListener("message", onTab);

  return () => {
    refresh.stop();
    tabs?.removeEventListener("message", onTab);
    tabs?.close();
  };
}
