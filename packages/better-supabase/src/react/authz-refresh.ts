import { AUTHZ_EVENT, authzUserTopic } from "../core/authz-topic.ts";

/** The broadcast message shape Realtime delivers for `realtime.send()`. */
interface BroadcastMessage {
  readonly payload?: unknown;
}

/** The part of a supabase-js `RealtimeChannel` the provider uses. */
export interface AuthzRefreshChannel {
  on(
    type: "broadcast",
    filter: { readonly event: string },
    callback: (message: BroadcastMessage) => void,
  ): AuthzRefreshChannel;
  subscribe(): AuthzRefreshChannel;
  unsubscribe(): Promise<unknown>;
}

/** The part of a browser supabase-js client the provider uses. */
export interface AuthzRefreshClient {
  channel(
    topic: string,
    options: { readonly config: { readonly private: boolean } },
  ): AuthzRefreshChannel;
  readonly auth: { refreshSession(): Promise<unknown> };
}

export interface AuthzRefreshOptions {
  readonly client: AuthzRefreshClient;
  readonly userId: string;
  /**
   * Runs after the token refresh, such as a Server Action and
   * `router.refresh()`.
   */
  readonly onChange: () => unknown;
  /** The `BroadcastChannel` name, or `false` for none. */
  readonly channel: string | false;
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

/** The `version` of a broadcast payload; Postgres `bigint` may arrive as text. */
function versionOf(payload: unknown): number | undefined {
  if (typeof payload !== "object" || payload === null) {
    return undefined;
  }

  const value: unknown = Object.entries(payload).find(
    ([name]) => name === "version",
  )?.[1];

  const version = typeof value === "string" ? Number(value) : value;

  return typeof version === "number" && Number.isFinite(version)
    ? version
    : undefined;
}

function errorOf(cause: unknown): Error {
  return cause instanceof Error ? cause : new Error(String(cause));
}

/**
 * Listens on the user's `authz:<uid>` topic. A visible tab that hears a new
 * version refreshes the token, runs `onChange` and tells the other tabs, which
 * run only `onChange`: the cookies are shared, so one refresh is enough. A
 * hidden tab waits until it becomes visible. Returns the cleanup.
 */
export function startAuthzRefresh(options: AuthzRefreshOptions): () => void {
  let seen = Number.NEGATIVE_INFINITY;
  let handled = Number.NEGATIVE_INFINITY;
  let stopped = false;

  const report = (cause: unknown): void => {
    options.onError?.(errorOf(cause));
  };

  const tabs =
    options.channel !== false && typeof BroadcastChannel === "function"
      ? new BroadcastChannel(options.channel)
      : undefined;

  const doc = "document" in globalThis ? globalThis.document : undefined;

  const visible = (): boolean => doc?.visibilityState !== "hidden";

  const refresh = async (version: number): Promise<void> => {
    handled = version;
    await options.client.auth.refreshSession();

    if (stopped) {
      return;
    }

    await options.onChange();

    const message: TabMessage = {
      type: "better-supabase:authz",
      userId: options.userId,
      version,
    };

    // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (1 finding).
    tabs?.postMessage(message);
  };

  const channel = options.client
    .channel(authzUserTopic(options.userId), { config: { private: true } })
    .on("broadcast", { event: AUTHZ_EVENT }, (message) => {
      const version = versionOf(message.payload);

      if (version === undefined || version <= seen) {
        return;
      }

      seen = version;

      if (visible()) {
        refresh(version).catch(report);
      }
    })
    .subscribe();

  const onTab = (event: MessageEvent): void => {
    const message: unknown = event.data;

    if (
      !isTabMessage(message) ||
      message.userId !== options.userId ||
      message.version <= handled
    ) {
      return;
    }

    handled = message.version;
    seen = Math.max(seen, message.version);
    Promise.resolve(options.onChange()).catch(report);
  };

  const onVisible = (): void => {
    if (visible() && seen > handled) {
      refresh(seen).catch(report);
    }
  };

  tabs?.addEventListener("message", onTab);
  doc?.addEventListener("visibilitychange", onVisible);

  return () => {
    stopped = true;
    tabs?.removeEventListener("message", onTab);
    tabs?.close();
    doc?.removeEventListener("visibilitychange", onVisible);
    channel.unsubscribe().catch(report);
  };
}
