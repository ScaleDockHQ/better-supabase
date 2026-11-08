import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { blockCall, DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";

/**
 * The `resumable-stream` publisher contract (`Publisher` from the package),
 * typed structurally so the package stays an optional peer.
 */
export interface ResumablePublisher {
  connect: () => Promise<unknown>;
  publish: (channel: string, message: string) => Promise<unknown>;
  set: (
    key: string,
    value: string,
    options?: { EX?: number },
  ) => Promise<unknown>;
  get: (key: string) => Promise<string | number | null>;
  incr: (key: string) => Promise<number>;
}

/** The `resumable-stream` subscriber contract (`Subscriber` from the package). */
export interface ResumableSubscriber {
  connect: () => Promise<unknown>;
  subscribe: (
    channel: string,
    callback: (message: string) => void,
  ) => Promise<void | number>;
  unsubscribe: (channel: string) => Promise<unknown>;
}

/** The part of a Supabase client the subscriber joins Realtime topics with. */
export interface ResumableRealtime {
  channel(
    topic: string,
    options?: { config?: { private?: boolean } },
  ): ResumableRealtimeChannel;
  removeChannel(channel: ResumableRealtimeChannel): PromiseLike<unknown>;
}

export interface ResumableRealtimeChannel {
  on(
    type: "broadcast",
    filter: { event: string },
    callback: (payload: { payload?: unknown }) => void,
  ): ResumableRealtimeChannel;
  subscribe(
    callback?: (status: string, error?: Error) => void,
  ): ResumableRealtimeChannel;
}

export interface PostgresPublisherOptions {
  /**
   * `sqlTransport(postgres.asService())`: the key-value functions are
   * service-only.
   */
  readonly transport: BlockTransport;
  /** The schema of the `streams` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface PostgresSubscriberOptions {
  /** A service-role Supabase client. */
  readonly realtime: ResumableRealtime;
  /** `blocks.streams.options.topic`. Defaults to `stream`. */
  readonly topic?: string;
}

const REALTIME_TOPIC = (topic: string, channel: string): string =>
  `${topic}:kv:${channel}`;

function fail(message: string): never {
  throw new Error(message);
}

function integer(value: unknown): number {
  const parsed = typeof value === "string" ? Number(value) : value;

  return typeof parsed === "number" && Number.isFinite(parsed)
    ? parsed
    : fail("stream_kv_incr returned a non-number");
}

/**
 * A `resumable-stream` publisher on Postgres: `get`, `set` and `incr` run
 * against `stream_entries`, and `publish` sends a Realtime broadcast. Pass it
 * with `postgresSubscriber` to `createResumableStreamContext` from
 * `resumable-stream/generic`, so a deployment that has Supabase needs no
 * Redis.
 */
export function postgresPublisher(
  options: PostgresPublisherOptions,
): ResumablePublisher {
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );

  const run = async <T>(
    fn: string,
    args: Record<string, unknown>,
    read: (value: unknown) => T,
  ): Promise<T> => {
    const result = await call(fn, args, read);

    if (!result.ok) {
      throw new Error(result.error.message);
    }

    return result.data;
  };

  return {
    connect: () => Promise.resolve(),
    get: (key) =>
      run("stream_kv_get", { key }, (value) =>
        typeof value === "string" ? value : null,
      ),
    set: (key, value, setOptions) =>
      run(
        "stream_kv_set",
        { key, value, ex: setOptions?.EX ?? null },
        () => "OK" as const,
      ),
    incr: (key) => run("stream_kv_incr", { key }, integer),
    publish: (channel, message) =>
      run("stream_kv_publish", { channel, message }, integer),
  };
}

/**
 * The subscriber that goes with `postgresPublisher`: each channel joins a
 * private Realtime topic, and `subscribe` resolves once the join is confirmed
 * so the first message can't be missed.
 */
export function postgresSubscriber(
  options: PostgresSubscriberOptions,
): ResumableSubscriber {
  const topic = options.topic ?? "stream";
  const joined = new Map<string, ResumableRealtimeChannel>();

  return {
    connect: () => Promise.resolve(),
    subscribe: (channel, callback) =>
      new Promise<void>((resolve, reject) => {
        const found = joined.get(channel);

        if (found) {
          void options.realtime.removeChannel(found);
        }

        const joinedChannel = options.realtime
          .channel(REALTIME_TOPIC(topic, channel), {
            config: { private: true },
          })
          .on("broadcast", { event: "message" }, ({ payload }) => {
            // SAFETY: stream_kv_publish sends { message: text }.
            const message =
              typeof payload === "object" &&
              payload !== null &&
              "message" in payload
                ? (payload as { readonly message: unknown }).message
                : undefined;

            if (typeof message === "string") {
              callback(message);
            }
          })
          .subscribe((status, error) => {
            if (status === "SUBSCRIBED") {
              resolve();
            } else if (
              status === "CHANNEL_ERROR" ||
              status === "TIMED_OUT" ||
              status === "CLOSED"
            ) {
              reject(error ?? new Error(`Realtime ${status} for ${channel}`));
            }
          });

        joined.set(channel, joinedChannel);
      }),
    unsubscribe: async (channel) => {
      const found = joined.get(channel);

      if (found) {
        joined.delete(channel);
        await options.realtime.removeChannel(found);
      }
    },
  };
}
