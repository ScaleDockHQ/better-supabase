import type {
  RelayEventSource,
  RelayEventSourceConstructor,
} from "../../src/realtime/relay.ts";
import type { RealtimeClient } from "../../src/realtime/topic.ts";

type Listener = (message: Record<string, unknown>) => void;

export interface FakeUpstream {
  readonly client: RealtimeClient;
  readonly open: readonly {
    readonly topic: string;
    readonly config: unknown;
  }[];
  readonly sent: readonly { topic: string; event: string; payload: unknown }[];
  refuse(value: boolean): void;
  emit(name: string, event: string, payload?: unknown): void;
  presence(name: string, state: Record<string, unknown[]>): void;
  status(name: string, state: string): void;
}

interface FakeChannel {
  readonly topic: string;
  readonly config: unknown;
  readonly listeners: { type: string; event: string; listener: Listener }[];
  status?: (state: string) => void;
  joined: boolean;
  presence: Record<string, unknown[]>;
}

/**
 * A realtime-js stand-in for the relay's upstream: `channel()` returns the open
 * channel for a topic, `emit` and `presence` play server messages, and
 * `httpSend` records what the relay broadcast.
 */
export function fakeUpstream(): FakeUpstream {
  const open: FakeChannel[] = [];
  const sent: { topic: string; event: string; payload: unknown }[] = [];
  let refuseJoin = false;

  const client = {
    channel: (name: string, options?: { config?: unknown }) => {
      const topic = `realtime:${name}`;

      const entry: FakeChannel = open.find((each) => each.topic === topic) ?? {
        topic,
        config: options?.config,
        listeners: [],
        joined: false,
        presence: {},
      };

      if (!open.includes(entry)) {
        open.push(entry);
      }

      const channel = {
        topic,
        entry,
        on: (type: string, filter: { event: string }, listener: Listener) => {
          entry.listeners.push({ type, event: filter.event, listener });

          return channel;
        },
        subscribe: (callback: (state: string) => void) => {
          entry.joined = true;
          entry.status = callback;
          queueMicrotask(() => {
            callback(refuseJoin ? "CHANNEL_ERROR" : "SUBSCRIBED");
          });

          return channel;
        },
        presenceState: () => entry.presence,
        track: async () => "ok",
        untrack: async () => "ok",
        send: async () => "ok",
        httpSend: async (event: string, payload: unknown) => {
          sent.push({ topic: name, event, payload });

          return { success: true };
        },
      };

      return channel;
    },
    getChannels: () => open,
    removeChannel: async (channel: { entry: FakeChannel }) => {
      const index = open.indexOf(channel.entry);

      if (index !== -1) {
        open.splice(index, 1);
      }

      return "ok" as const;
    },
    realtime: { setAuth: async () => undefined },
  };

  const find = (name: string) =>
    open.find((each) => each.topic === `realtime:${name}`);

  return {
    // SAFETY: the fake implements the members the relay and joinTopic call.
    client: client as unknown as RealtimeClient,
    open,
    sent,
    refuse: (value) => {
      refuseJoin = value;
    },
    emit: (name, event, payload = {}) => {
      for (const each of find(name)?.listeners ?? []) {
        if (each.type === "broadcast") {
          each.listener({ event, payload });
        }
      }
    },
    presence: (name, state) => {
      const entry = find(name);

      if (!entry) {
        return;
      }

      entry.presence = state;

      for (const each of entry.listeners) {
        if (each.type === "presence") {
          each.listener({});
        }
      }
    },
    status: (name, state) => {
      find(name)?.status?.(state);
    },
  };
}

/**
 * Parses server-sent events out of a byte stream.
 *
 * @yields {{ event: string; data: string }} Each event with its name and joined
 *   data lines.
 */
export async function* sseEvents(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<{ event: string; data: string }> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  for (;;) {
    const { value, done } = await reader.read();

    if (done) {
      return;
    }

    buffer += decoder.decode(value, { stream: true });
    let end = buffer.indexOf("\n\n");

    while (end !== -1) {
      const block = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      end = buffer.indexOf("\n\n");
      let event = "message";
      const data: string[] = [];

      for (const line of block.split("\n")) {
        if (line.startsWith("event: ")) {
          event = line.slice(7);
        } else if (line.startsWith("data: ")) {
          data.push(line.slice(6));
        } else if (line.startsWith(":")) {
          event = "comment";
          data.push(line.slice(1).trim());
        } else if (line.startsWith("retry: ")) {
          event = "retry";
          data.push(line.slice(7));
        }
      }

      yield { event, data: data.join("\n") };
    }
  }
}

/**
 * An `EventSource` that requests the relay's `GET` handler in process,
 * dispatches its events and reconnects when a stream ends, like a browser.
 */
export function inProcessEventSource(
  handler: (request: Request) => Promise<Response>,
  init: RequestInit = {},
): {
  readonly EventSource: RelayEventSourceConstructor;
  readonly sources: RelayEventSource[];
} {
  const sources: RelayEventSource[] = [];

  class InProcessEventSource implements RelayEventSource {
    readyState = 0;
    readonly url: string;
    readonly #listeners = new Map<
      string,
      ((event: { data?: unknown }) => void)[]
    >();
    readonly #abort = new AbortController();

    constructor(url: string) {
      this.url = url;
      sources.push(this);
      void this.#run();
    }

    addEventListener(
      type: string,
      listener: (event: { readonly data?: unknown }) => void,
    ): void {
      const list = this.#listeners.get(type) ?? [];
      list.push(listener);
      this.#listeners.set(type, list);
    }

    close(): void {
      this.readyState = 2;
      this.#abort.abort();
    }

    #dispatch(type: string, data?: string): void {
      for (const listener of this.#listeners.get(type) ?? []) {
        listener(data === undefined ? {} : { data });
      }
    }

    async #run(): Promise<void> {
      while (this.readyState !== 2) {
        const response = await handler(
          new Request(new URL(this.url, "https://app.test"), {
            ...init,
            signal: this.#abort.signal,
          }),
        );

        if (response.status !== 200 || !response.body) {
          this.readyState = 2;
          this.#dispatch("error");

          return;
        }

        this.readyState = 1;

        try {
          for await (const message of sseEvents(response.body)) {
            if (this.readyState === 2) {
              return;
            }

            this.#dispatch(message.event, message.data);
          }
        } catch {
          // Aborted by close().
        }

        if (this.readyState === 2) {
          return;
        }

        this.readyState = 0;
        this.#dispatch("error");
        await new Promise((resolve) => {
          setTimeout(resolve, 1);
        });
      }
    }
  }

  return { EventSource: InProcessEventSource, sources };
}
