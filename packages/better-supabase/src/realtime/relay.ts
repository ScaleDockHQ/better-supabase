import type { RealtimeClient } from "./topic.ts";
import type { TopicPort } from "./watch-topic.ts";

import { topicPort } from "./watch-topic.ts";

/** The `EventSource` the relay client reads with; the browser's fits. */
export interface RelayEventSource {
  readonly readyState: number;
  addEventListener(
    type: string,
    listener: (event: { readonly data?: unknown }) => void,
  ): void;
  close(): void;
}

export type RelayEventSourceConstructor = new (
  url: string,
  init?: { withCredentials?: boolean },
) => RelayEventSource;

export interface RelayClientOptions {
  /** Defaults to the global `EventSource`. */
  readonly EventSource?: RelayEventSourceConstructor;
  /** `fetch` for broadcasts; defaults to the global one. */
  readonly fetch?: typeof fetch;
  /**
   * Milliseconds from `subscribe()` to the first join. Until then, a failed
   * attempt is retried with backoff; when the time is up, the channel reports
   * `TIMED_OUT` and stops. Defaults to 15000.
   */
  readonly timeoutMs?: number;
  /**
   * The longest wait between reconnects after a stream closed or a join failed
   * for a reason that may pass. Defaults to 30000.
   */
  readonly maxBackoffMs?: number;
}

type Status = "SUBSCRIBED" | "TIMED_OUT" | "CLOSED" | "CHANNEL_ERROR";

type StatusCallback = (status: Status, error?: Error) => void;

interface Listener {
  readonly event: string;
  readonly callback: (message: Record<string, unknown>) => void;
}

type SendResponse = "ok" | "timed out" | "error";

type HttpSendResponse =
  | { readonly success: true }
  | {
      readonly success: false;
      readonly status: number;
      readonly error: string;
    };

interface RelayChannel {
  readonly topic: string;
  on(
    type: string,
    filter: { readonly event?: string },
    callback: (message: Record<string, unknown>) => void,
  ): RelayChannel;
  subscribe(callback?: StatusCallback): RelayChannel;
  unsubscribe(): Promise<SendResponse>;
  presenceState(): Record<string, unknown[]>;
  track(state: Record<string, unknown>): Promise<SendResponse>;
  untrack(): Promise<SendResponse>;
  send(message: {
    readonly type: string;
    readonly event: string;
    readonly payload?: unknown;
  }): Promise<SendResponse>;
  httpSend(event: string, payload: unknown): Promise<HttpSendResponse>;
}

const CLOSED_STATE = 2;

function parse(event: { readonly data?: unknown }): unknown {
  if (typeof event.data !== "string") {
    return undefined;
  }

  try {
    return JSON.parse(event.data);
  } catch {
    return undefined;
  }
}

/** The runtime's `EventSource`, read without assuming DOM types. */
function globalEventSource(): RelayEventSourceConstructor | undefined {
  const value: unknown =
    "EventSource" in globalThis ? globalThis.EventSource : undefined;

  // SAFETY: a global `EventSource` function is the WHATWG constructor, whose
  // instances have `readyState`, `addEventListener` and `close`.
  return typeof value === "function"
    ? (value as RelayEventSourceConstructor)
    : undefined;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

async function problemDetail(response: Response): Promise<string> {
  const problem: unknown = await response.json().catch(() => undefined);

  return isRecord(problem) && typeof problem["detail"] === "string"
    ? problem["detail"]
    : isRecord(problem) && typeof problem["title"] === "string"
      ? problem["title"]
      : response.statusText;
}

/**
 * A Realtime client that joins topics through `realtimeRelay` on the server
 * instead of a browser connection with the user's token: for support sessions
 * ("view as user") and apps that keep sessions in httpOnly cookies. It has the
 * `RealtimeClient` surface, so `defineTopic(...).subscribe`, `send`,
 * `liveQuery`, `watchTopic` and the React hooks take it unchanged. Each topic
 * is one server-sent event stream that reconnects on its own and reports a
 * rejoin after a gap, so live queries refetch. Presence states arrive, but
 * `track` answers `error`: presence is not relayed upstream.
 *
 * ```ts
 * const realtime = relayRealtimeClient("/api/realtime");
 * using sub = notifications.subscribe(realtime, { userId }, handlers);
 * ```
 */
export function relayRealtimeClient(
  url: string,
  options: RelayClientOptions = {},
): RealtimeClient {
  const channels: RelayChannel[] = [];
  const timeoutMs = options.timeoutMs ?? 15_000;
  const maxBackoffMs = options.maxBackoffMs ?? 30_000;
  const channelClose = new WeakMap<RelayChannel, () => void>();

  const post = async (
    topic: string,
    event: string,
    payload: unknown,
  ): Promise<HttpSendResponse> => {
    const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);

    try {
      const response = await doFetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ topic, event, payload }),
      });

      if (response.ok) {
        await response.body?.cancel();

        return { success: true };
      }

      return {
        success: false,
        status: response.status,
        error: await problemDetail(response),
      };
    } catch (cause) {
      return {
        success: false,
        status: 0,
        error: cause instanceof Error ? cause.message : String(cause),
      };
    }
  };

  const failureOf = async (streamUrl: string): Promise<string | undefined> => {
    const controller = new AbortController();

    try {
      const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);

      const response = await doFetch(streamUrl, {
        credentials: "include",
        headers: { accept: "text/event-stream" },
        signal: controller.signal,
      });

      return response.ok
        ? undefined
        : `${String(response.status)} ${await problemDetail(response)}`.trim();
    } catch {
      return undefined;
    } finally {
      controller.abort();
    }
  };

  const create = (name: string): RelayChannel => {
    const topic = `realtime:${name}`;
    const separator = url.includes("?") ? "&" : "?";
    const streamUrl = `${url}${separator}topic=${encodeURIComponent(name)}`;
    const listeners: Listener[] = [];
    let presence: Record<string, unknown[]> = {};
    let source: RelayEventSource | undefined;
    let status: StatusCallback | undefined;
    let subscribed = false;
    let ending = false;
    let removed = false;
    let stopped = false;
    let failed = false;
    let backoff = 1000;
    let joinTimer: ReturnType<typeof setTimeout> | undefined;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;

    const dispatch = (
      type: string,
      event: string,
      message: Record<string, unknown>,
    ) => {
      for (const listener of listeners) {
        if (
          listener.event === `${type}:*` ||
          listener.event === `${type}:${event}`
        ) {
          listener.callback(message);
        }
      }
    };

    const timedOut = (): void => {
      if (subscribed || removed) {
        return;
      }

      stopped = true;
      clearTimeout(retryTimer);
      source?.close();
      source = undefined;

      if (!failed) {
        status?.("TIMED_OUT");

        return;
      }

      void failureOf(streamUrl).then((failure) => {
        if (!removed) {
          status?.(
            "TIMED_OUT",
            new Error(
              failure === undefined
                ? `The relay could not join ${name}`
                : `The relay could not join ${name}: ${failure}`,
            ),
          );
        }
      });
    };

    const open = (): void => {
      if (removed || stopped) {
        return;
      }

      const Source = options.EventSource ?? globalEventSource();

      if (Source === undefined) {
        clearTimeout(joinTimer);
        status?.(
          "CHANNEL_ERROR",
          new Error("relayRealtimeClient needs EventSource"),
        );

        return;
      }

      const next = new Source(streamUrl, { withCredentials: true });
      let joined = false;

      const retry = (message: string): void => {
        next.close();
        source = undefined;
        failed = true;
        status?.("CHANNEL_ERROR", new Error(message));
        retryTimer = setTimeout(open, backoff);
        backoff = Math.min(backoff * 2, maxBackoffMs);
      };

      source = next;

      next.addEventListener("status", (event) => {
        const data = parse(event);

        if (!isRecord(data) || source !== next) {
          return;
        }

        if (data["status"] === "subscribed") {
          clearTimeout(joinTimer);
          subscribed = true;
          joined = true;
          ending = false;
          backoff = 1000;
          status?.("SUBSCRIBED");
        } else if (data["status"] === "error") {
          status?.("CHANNEL_ERROR", new Error(`Realtime error on ${name}`));
        }
      });

      next.addEventListener("broadcast", (event) => {
        const data = parse(event);

        if (!isRecord(data) || typeof data["event"] !== "string") {
          return;
        }

        dispatch("broadcast", data["event"], {
          type: "broadcast",
          event: data["event"],
          payload: data["payload"],
        });
      });

      next.addEventListener("presence", (event) => {
        const data = parse(event);

        if (!isRecord(data)) {
          return;
        }

        presence = Object.fromEntries(
          Object.entries(data).filter((entry): entry is [string, unknown[]] =>
            Array.isArray(entry[1]),
          ),
        );
        dispatch("presence", "sync", {});
      });

      next.addEventListener("end", (event) => {
        if (removed || source !== next) {
          return;
        }

        if (joined) {
          ending = true;

          return;
        }

        const data = parse(event);

        const reason =
          isRecord(data) && typeof data["reason"] === "string"
            ? data["reason"]
            : "closed";

        retry(`The relay could not join ${name} (${reason}); retrying`);
      });

      next.addEventListener("error", () => {
        if (removed || source !== next) {
          return;
        }

        if (next.readyState !== CLOSED_STATE) {
          if (subscribed && !ending) {
            status?.(
              "CHANNEL_ERROR",
              new Error(`The relay connection for ${name} dropped`),
            );
          }

          return;
        }

        retry(
          subscribed
            ? `The relay closed ${name}; reconnecting`
            : `The relay could not join ${name}; retrying`,
        );
      });
    };

    const close = (): void => {
      removed = true;
      clearTimeout(joinTimer);
      clearTimeout(retryTimer);
      source?.close();
      source = undefined;
    };

    const channel: RelayChannel = {
      topic,
      on(type, filter, callback) {
        listeners.push({ event: `${type}:${filter.event ?? "*"}`, callback });

        return channel;
      },
      subscribe(callback) {
        if (status !== undefined || removed) {
          throw new Error(
            `tried to subscribe multiple times to ${name} on the relay`,
          );
        }

        status = callback ?? (() => undefined);
        joinTimer = setTimeout(timedOut, timeoutMs);
        open();

        return channel;
      },
      unsubscribe: () => {
        close();
        status?.("CLOSED");

        return Promise.resolve("ok");
      },
      presenceState: () => presence,
      track: () => Promise.resolve("error"),
      untrack: () => Promise.resolve("error"),
      send: async (message) =>
        (await post(name, message.event, message.payload)).success
          ? "ok"
          : "error",
      httpSend: (event, payload) => post(name, event, payload),
    };

    channelClose.set(channel, close);

    return channel;
  };

  const relay = {
    channel: (name: string): RelayChannel => {
      const topic = `realtime:${name}`;
      const open = channels.find((each) => each.topic === topic);

      if (open) {
        return open;
      }

      const channel = create(name);
      channels.push(channel);

      return channel;
    },
    getChannels: (): RelayChannel[] => [...channels],
    removeChannel: (channel: RelayChannel): Promise<"ok"> => {
      const index = channels.indexOf(channel);

      if (index !== -1) {
        channels.splice(index, 1);
      }

      channelClose.get(channel)?.();

      return Promise.resolve("ok");
    },
    realtime: { setAuth: (): Promise<void> => Promise.resolve() },
  };

  // SAFETY: `relay` implements every member of RealtimeClient and its channels
  // that `defineTopic`, `watchTopic`, `liveQuery` and the React hooks call.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- a structural stand-in for supabase-js's class types, which carry private members.
  return relay as unknown as RealtimeClient;
}

/**
 * The block controllers' realtime port over `realtimeRelay`:
 * `topicPort(relayRealtimeClient(url, options))`.
 */
export function relayTopicPort(
  url: string,
  options: RelayClientOptions = {},
): TopicPort {
  return topicPort(relayRealtimeClient(url, options));
}
