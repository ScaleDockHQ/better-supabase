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
  rpc?(fn: "caller_authz_version"): PromiseLike<AuthzRpcResult>;
  /**
   * Selects the schema of the version function (supabase-js `schema()`).
   * Without it, `rpc` reads whatever schema the client is set to.
   */
  schema?(name: string): {
    rpc(fn: "caller_authz_version"): PromiseLike<AuthzRpcResult>;
  };
}

interface AuthzRpcResult {
  readonly data: unknown;
  readonly error: unknown;
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
  /**
   * The schema of `caller_authz_version()`, read through the client's
   * `schema()`. Defaults to `api`, where the sessions module creates it.
   */
  readonly schema?: string;
  /**
   * The live authz version the server read for this page (the bootstrap's
   * `authzVersion`). The first join reports it instead of calling
   * `caller_authz_version()`; later joins, after a reconnect, still read it.
   */
  readonly liveVersion?: number | null;
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

/** Waits for an idle moment so the join does not compete with the first render. */
function whenIdle(run: () => void): () => void {
  const idle =
    "requestIdleCallback" in globalThis
      ? globalThis.requestIdleCallback
      : undefined;

  if (typeof idle === "function") {
    const id = idle(run, { timeout: 2000 });

    return () => {
      globalThis.cancelIdleCallback(id);
    };
  }

  const timer = setTimeout(run, 1);

  return () => {
    clearTimeout(timer);
  };
}

interface SharedChannel {
  readonly listeners: Set<(version: number) => void>;
  readonly joins: Set<() => void>;
  refs: number;
  joined: boolean;
  cancelJoin: (() => void) | undefined;
  channel: AuthzRefreshChannel | undefined;
}

/** One channel per client, topic and event, shared by every listener on it. */
const SHARED = new WeakMap<object, Map<string, SharedChannel>>();

/**
 * The default version source: broadcasts on the user's private topic, and
 * `caller_authz_version()` (in the `api` schema unless `schema` says otherwise)
 * for `current()`. The channel joins when the browser is idle, and one channel
 * serves every source for the same client and topic, so listeners that overlap
 * (a remounted provider, two providers) join once, and a join that is stopped
 * before the idle moment never happens. The first join reports `liveVersion`
 * when the server passed it in; every later join (after a reconnect) reads the
 * live version, so a change made while the channel was down still arrives.
 */
export function realtimeVersionSource(
  client: AuthzRefreshClient,
  userId: string,
  options: AuthzTopicOptions & {
    readonly onError?: (error: Error) => void;
  } = {},
): LiveVersionSource {
  const current = async (): Promise<number | undefined> => {
    const scoped = client.schema?.(options.schema ?? "api");
    const rpc = scoped ? scoped.rpc.bind(scoped) : client.rpc?.bind(client);

    if (!rpc) {
      return undefined;
    }

    const { data, error } = await rpc("caller_authz_version");

    if (error) {
      throw errorOf(error);
    }

    return versionFrom(data);
  };

  const sharedOf = (key: string): SharedChannel => {
    const byKey = SHARED.get(client) ?? new Map<string, SharedChannel>();
    SHARED.set(client, byKey);

    const existing = byKey.get(key);

    if (existing) {
      return existing;
    }

    const created: SharedChannel = {
      listeners: new Set(),
      joins: new Set(),
      refs: 0,
      joined: false,
      cancelJoin: undefined,
      channel: undefined,
    };

    byKey.set(key, created);

    return created;
  };

  return {
    current,
    subscribe(listener, onLive = listener) {
      const topic = (options.topic ?? authzUserTopic)(userId);
      const event = options.event ?? AUTHZ_EVENT;
      const key = `${topic}\u0000${event}`;
      const shared = sharedOf(key);
      let stopped = false;
      let joins = 0;

      const onJoin = (): void => {
        joins += 1;

        if (joins === 1 && typeof options.liveVersion === "number") {
          onLive(options.liveVersion);

          return;
        }

        current().then(
          (version) => {
            if (!stopped && version !== undefined) {
              onLive(version);
            }
          },
          (cause: unknown) => options.onError?.(errorOf(cause)),
        );
      };

      shared.refs += 1;
      shared.listeners.add(listener);
      shared.joins.add(onJoin);

      if (shared.joined) {
        onJoin();
      } else if (shared.channel === undefined && !shared.cancelJoin) {
        shared.cancelJoin = whenIdle(() => {
          shared.cancelJoin = undefined;
          shared.channel = client
            .channel(topic, { config: { private: true } })
            .on("broadcast", { event }, (message) => {
              const version = payloadVersion(message.payload);

              if (version !== undefined) {
                for (const each of shared.listeners) {
                  each(version);
                }
              }
            })
            .subscribe((status) => {
              if (status === "SUBSCRIBED") {
                shared.joined = true;

                for (const each of shared.joins) {
                  each();
                }
              }
            });
        });
      }

      return () => {
        stopped = true;
        shared.listeners.delete(listener);
        shared.joins.delete(onJoin);
        shared.refs -= 1;

        if (shared.refs > 0) {
          return;
        }

        shared.cancelJoin?.();
        SHARED.get(client)?.delete(key);
        shared.channel?.unsubscribe().catch((cause: unknown) => {
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
