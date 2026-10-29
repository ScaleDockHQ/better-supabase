import { AUTHZ_EVENT, authzUserTopic } from "../core/authz-topic.ts";

/** The broadcast message shape Realtime delivers for `realtime.send()`. */
interface BroadcastMessage {
  readonly payload?: unknown;
}

/** The part of a supabase-js `RealtimeChannel` the refresh uses. */
export interface AuthzRefreshChannel {
  on(
    type: "broadcast",
    filter: { readonly event: string },
    callback: (message: BroadcastMessage) => void,
  ): AuthzRefreshChannel;
  subscribe(callback?: (status: string) => void): AuthzRefreshChannel;
  unsubscribe(): Promise<unknown>;
}

/** The part of a supabase-js client the refresh uses. */
export interface AuthzRefreshClient {
  channel(
    topic: string,
    options: { readonly config: { readonly private: boolean } },
  ): AuthzRefreshChannel;
  readonly auth: { refreshSession(): Promise<unknown> };
  /**
   * Reads `api.caller_authz_version()` to catch up on a broadcast missed while
   * the channel was down. Without it, only broadcasts refresh.
   */
  rpc?(
    fn: "caller_authz_version",
  ): PromiseLike<{ readonly data: unknown; readonly error: unknown }>;
}

/** Whether the app may refresh now: a visible tab, a foreground app. */
export interface AuthzPresence {
  active(): boolean;
  /** Calls `listener` each time the app becomes active; returns the cleanup. */
  onActive(listener: () => void): () => void;
}

export interface AuthzTopicOptions {
  /** The topic for `userId`. Defaults to `authz:<uid>`. */
  readonly topic?: (userId: string) => string;
  /** The broadcast event. Defaults to `changed`. */
  readonly event?: string;
}

/** A version from a broadcast payload or an RPC; `bigint` may arrive as text. */
function versionFrom(value: unknown): number | undefined {
  const version = typeof value === "string" ? Number(value) : value;

  return typeof version === "number" && Number.isFinite(version)
    ? version
    : undefined;
}

function payloadVersion(payload: unknown): number | undefined {
  if (typeof payload !== "object" || payload === null) {
    return undefined;
  }

  return versionFrom(
    Object.entries(payload).find(([name]) => name === "version")?.[1],
  );
}

export function errorOf(cause: unknown): Error {
  return cause instanceof Error ? cause : new Error(String(cause));
}

/**
 * A version source that may also report the live version on its own, such as on
 * each channel join. A plain `AuthzVersionSource` is one.
 */
export interface LiveVersionSource {
  current(): Promise<number | undefined>;
  subscribe(
    listener: (version: number) => void,
    onLive?: (version: number) => void,
  ): () => void;
}

/**
 * The default version source: broadcasts on the user's private topic, and
 * `api.caller_authz_version()` for `current()`. Each time the channel joins
 * (the first time and after a reconnect), it reads the live version and reports
 * it, so a change made while the channel was down still arrives.
 */
export function realtimeVersionSource(
  client: AuthzRefreshClient,
  userId: string,
  options: AuthzTopicOptions & {
    readonly onError?: (error: Error) => void;
  } = {},
): LiveVersionSource {
  const current = async (): Promise<number | undefined> => {
    if (!client.rpc) {
      return undefined;
    }

    const { data, error } = await client.rpc("caller_authz_version");

    if (error) {
      throw errorOf(error);
    }

    return versionFrom(data);
  };

  return {
    current,
    subscribe(listener, onLive = listener) {
      const topic = (options.topic ?? authzUserTopic)(userId);
      let stopped = false;

      const catchUp = (): void => {
        current().then(
          (version) => {
            if (!stopped && version !== undefined) {
              onLive(version);
            }
          },
          (cause: unknown) => options.onError?.(errorOf(cause)),
        );
      };

      const channel = client
        .channel(topic, { config: { private: true } })
        .on("broadcast", { event: options.event ?? AUTHZ_EVENT }, (message) => {
          const version = payloadVersion(message.payload);

          if (version !== undefined) {
            listener(version);
          }
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            catchUp();
          }
        });

      return () => {
        stopped = true;
        channel.unsubscribe().catch((cause: unknown) => {
          options.onError?.(errorOf(cause));
        });
      };
    },
  };
}

export interface AuthzRefreshCore {
  readonly source: LiveVersionSource;
  readonly presence: AuthzPresence;
  /** The version in the current token, or `null` without the claim. */
  readonly tokenVersion: () => number | null | Promise<number | null>;
  /** Refreshes the token. */
  readonly refresh: () => Promise<unknown>;
  /** Runs after each refresh, with the version it caught up to. */
  readonly onRefreshed: (version: number) => unknown;
  readonly onError?: (error: Error) => void;
}

/**
 * Refreshes the token once per newer version: a version the source reports
 * while the app is active, or the live version when the app becomes active and
 * the token predates it. Returns the cleanup.
 */
export function runAuthzRefresh(core: AuthzRefreshCore): {
  /**
   * Marks `version` handled elsewhere (another tab refreshed); false when it
   * was handled already.
   */
  readonly handled: (version: number) => boolean;
  readonly stop: () => void;
} {
  let seen = Number.NEGATIVE_INFINITY;
  let handled = Number.NEGATIVE_INFINITY;
  let stopped = false;
  let running: Promise<void> | undefined;

  const report = (cause: unknown): void => {
    core.onError?.(errorOf(cause));
  };

  const refresh = async (version: number): Promise<void> => {
    handled = Math.max(handled, version);
    await core.refresh();

    if (!stopped) {
      await core.onRefreshed(version);
    }
  };

  /**
   * `live` marks a version read from the database rather than broadcast: it
   * says what the user has now, not that it changed. Without a version in the
   * token there is nothing to compare it with, so it only sets the baseline.
   */
  const consider = (version: number, live = false): void => {
    if (!live) {
      seen = Math.max(seen, version);
    }

    if (stopped || version <= handled || !core.presence.active()) {
      return;
    }

    const step = async (): Promise<void> => {
      if (stopped || version <= handled) {
        return;
      }

      const token = await core.tokenVersion();

      if (token === null ? live : version <= token) {
        handled = Math.max(handled, version);

        return;
      }

      await refresh(version);
    };

    running = (running ?? Promise.resolve()).then(step).catch(report);
  };

  const stopSource = core.source.subscribe(
    (version) => {
      consider(version);
    },
    (version) => {
      consider(version, true);
    },
  );

  const stopPresence = core.presence.onActive(() => {
    if (seen > handled) {
      consider(seen);
    }

    core.source.current().then((version) => {
      if (version !== undefined) {
        consider(version, true);
      }
    }, report);
  });

  return {
    handled: (version) => {
      seen = Math.max(seen, version);

      if (version <= handled) {
        return false;
      }

      handled = version;

      return true;
    },
    stop: () => {
      stopped = true;
      stopSource();
      stopPresence();
    },
  };
}
