import type { BlockTransport } from "../../src/core/block-transport.ts";
import type {
  RedisStreamClient,
  RedisStreamSubscriber,
} from "../../src/streams/redis/index.ts";

/** The commands `redisStreamStore` sends, kept in maps. */
export function fakeRedis(): {
  client: RedisStreamClient;
  subscriber: RedisStreamSubscriber;
  published: string[];
} {
  const hashes = new Map<string, Map<string, string>>();
  const lists = new Map<string, string[]>();
  const listeners = new Map<string, Set<(message: string) => void>>();
  const published: string[] = [];
  const hash = (key: string): Map<string, string> => {
    let entry = hashes.get(key);
    if (!entry) hashes.set(key, (entry = new Map()));
    return entry;
  };
  const list = (key: string): string[] => {
    let entry = lists.get(key);
    if (!entry) lists.set(key, (entry = []));
    return entry;
  };
  const client: RedisStreamClient = {
    async hSetNX(key, field, value) {
      const entry = hash(key);
      if (entry.has(field)) return 0;
      entry.set(field, value);
      return 1;
    },
    async hSet(key, field, value) {
      hash(key).set(field, value);
      return 1;
    },
    async hGetAll(key) {
      return Object.fromEntries(hashes.get(key) ?? []);
    },
    async rPush(key, elements) {
      return list(key).push(...elements);
    },
    async lRange(key, start, stop) {
      return list(key).slice(start, stop + 1);
    },
    async lLen(key) {
      return list(key).length;
    },
    async expire() {
      return 1;
    },
    async publish(channel, message) {
      published.push(`${channel} ${message}`);
      for (const listener of listeners.get(channel) ?? []) listener(message);
      return 1;
    },
  };
  const subscriber: RedisStreamSubscriber = {
    async subscribe(channel, listener) {
      let set = listeners.get(channel);
      if (!set) listeners.set(channel, (set = new Set()));
      set.add(listener);
    },
    async unsubscribe(channel, listener) {
      listeners.get(channel)?.delete(listener);
    },
  };
  return { client, subscriber, published };
}

interface FakeStream {
  chunks: string[];
  closed: boolean;
  cancelled: boolean;
}

const raise = (message: string, code: string, hint: string): never => {
  throw Object.assign(new Error(message), { code, hint });
};

/** The `streams` module's functions, in memory, behind a `BlockTransport`. */
export function fakeStreamsTransport(): {
  transport: BlockTransport;
  calls: { fn: string; args: Readonly<Record<string, unknown>> }[];
} {
  const streams = new Map<string, FakeStream>();
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];
  const must = (id: unknown): FakeStream => {
    const stream = streams.get(String(id));
    return (
      stream ??
      raise(`stream ${String(id)} does not exist`, "P0002", "STREAM_NOT_FOUND")
    );
  };
  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push({ fn, args });
      const id = String(args["stream_id"]);
      switch (fn) {
        case "stream_open":
          if (streams.has(id)) return false;
          streams.set(id, { chunks: [], closed: false, cancelled: false });
          return true;
        case "stream_append": {
          const stream = must(id);
          if (stream.closed) raise("closed", "P0001", "STREAM_CLOSED");
          const from = Number(args["from_idx"]);
          const chunks = (args["chunks"] as string[] | undefined) ?? [];
          if (from > stream.chunks.length) raise("gap", "P0001", "STREAM_GAP");
          stream.chunks.push(...chunks.slice(stream.chunks.length - from));
          return {
            next: Math.max(stream.chunks.length, from + chunks.length),
            cancelled: stream.cancelled,
          };
        }
        case "stream_read": {
          const stream = streams.get(id);
          const from = Number(args["from_idx"] ?? 0);
          if (!stream)
            return {
              found: false,
              chunks: [],
              next: from,
              done: true,
              cancelled: false,
            };
          const chunks = stream.chunks.slice(
            from,
            from + Number(args["max"] ?? 1000),
          );
          const next = from + chunks.length;
          return {
            found: true,
            chunks,
            next,
            done: stream.closed && next >= stream.chunks.length,
            cancelled: stream.cancelled,
          };
        }
        case "stream_status": {
          const stream = streams.get(id);
          return stream
            ? {
                next: stream.chunks.length,
                closed: stream.closed,
                cancelled: stream.cancelled,
              }
            : null;
        }
        case "stream_close": {
          const stream = streams.get(id);
          if (!stream || stream.closed) return false;
          stream.closed = true;
          return true;
        }
        case "stream_cancel": {
          const stream = streams.get(id);
          if (!stream || stream.closed || stream.cancelled) return false;
          stream.cancelled = true;
          return true;
        }
        case "purge_streams":
          return 0;
        default:
          throw new Error(`unexpected ${fn}`);
      }
    },
  };
  return { transport, calls };
}
