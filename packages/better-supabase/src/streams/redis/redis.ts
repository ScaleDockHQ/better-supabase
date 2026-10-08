import type { StreamPage, StreamStatus, StreamStore } from "../store.ts";

import { isRecord } from "../../blocks/shared.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { pollingRead } from "../store.ts";

/**
 * The commands the store sends, as node-redis 5 and 6 (`createClient()`)
 * name them. Any client with these methods works.
 */
export interface RedisStreamClient {
  hSetNX(key: string, field: string, value: string): Promise<unknown>;
  hSet(key: string, field: string, value: string): Promise<unknown>;
  hGetAll(key: string): Promise<unknown>;
  rPush(key: string, elements: string[]): Promise<unknown>;
  lRange(key: string, start: number, stop: number): Promise<unknown>;
  lLen(key: string): Promise<unknown>;
  expire(key: string, seconds: number): Promise<unknown>;
  publish(channel: string, message: string): Promise<unknown>;
}

/** A client in subscriber mode, such as `client.duplicate()` after `connect()`. */
export interface RedisStreamSubscriber {
  subscribe(
    channel: string,
    listener: (message: string) => void,
  ): Promise<unknown>;
  unsubscribe(
    channel: string,
    listener: (message: string) => void,
  ): Promise<unknown>;
}

interface RedisStreamSharedOptions {
  /** Key and channel prefix. Defaults to `bs:stream`. */
  readonly keyPrefix?: string;
  /** How long a stream opened without a `ttl` lives. Defaults to `'1 day'`. */
  readonly ttl?: number | string;
  /** Milliseconds between reads of an idle stream: 250 by default, 2000 with `subscriber`. */
  readonly pollMs?: number;
  /** Chunks per read. Defaults to 1000. */
  readonly batch?: number;
}

export type RedisStreamStoreOptions = RedisStreamSharedOptions &
  (
    | {
        readonly client: RedisStreamClient;
        /** Wakes readers on each batch; without it they poll. */
        readonly subscriber?: RedisStreamSubscriber;
      }
    | {
        /**
         * Connects with `redis` (node-redis, an optional peer) on first use,
         * with a duplicate connection that wakes readers.
         */
        readonly url: string;
      }
  );

interface Connected {
  readonly client: RedisStreamClient;
  readonly subscriber: RedisStreamSubscriber | undefined;
}

interface NodeRedisClient extends RedisStreamClient, RedisStreamSubscriber {
  connect(): Promise<unknown>;
  duplicate(): NodeRedisClient;
}

const isNodeRedis = (
  value: unknown,
): value is { createClient(options: { url: string }): NodeRedisClient } =>
  isRecord(value) && typeof value["createClient"] === "function";

/**
 * Loads `redis` on first use. The specifier is a variable so bundlers leave
 * the optional peer out of apps that pass their own client.
 */
async function loadRedis(): Promise<unknown> {
  const specifier = "redis";
  try {
    return await import(specifier);
  } catch {
    return undefined;
  }
}

async function connectUrl(
  url: string,
  load: () => Promise<unknown>,
): Promise<Connected> {
  const module = await load();
  if (!isNodeRedis(module))
    throw new TypeError(
      "redisStreamStore({ url }) needs the redis package: pnpm add redis, or pass a connected client",
    );
  const client = module.createClient({ url });
  const subscriber = client.duplicate();
  await Promise.all([client.connect(), subscriber.connect()]);
  return { client, subscriber };
}

const DAY = 86_400;
const UNITS: Readonly<Record<string, number>> = {
  second: 1,
  minute: 60,
  hour: 3600,
  day: DAY,
};
const INTERVAL = /^(\d+)\s*(second|minute|hour|day)s?$/;

function ttlSeconds(value: number | string): number | undefined {
  if (typeof value === "number")
    return value > 0 ? Math.ceil(value) : undefined;
  const match = INTERVAL.exec(value.trim());
  const unit = match?.[2] === undefined ? undefined : UNITS[match[2]];
  return match && unit ? Number(match[1]) * unit : undefined;
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

/**
 * A `StreamStore` on Redis, for apps that keep live output out of Postgres.
 * Chunks live in a list and the state in a hash, both expiring after the
 * stream's `ttl`, so `purge` has nothing to do and resolves with 0. Redis
 * has no row-level security: check that the caller owns the stream before
 * `read` or `cancel`.
 */
export function redisStreamStore(
  options: RedisStreamStoreOptions,
  load: () => Promise<unknown> = loadRedis,
): StreamStore {
  let connected: Promise<Connected> | undefined =
    "client" in options
      ? Promise.resolve({
          client: options.client,
          subscriber: options.subscriber,
        })
      : undefined;
  const connection = (): Promise<Connected> => {
    if (connected) return connected;
    if (!("url" in options))
      throw new TypeError("redisStreamStore needs a client or a url");
    const pending = connectUrl(options.url, load);
    connected = pending;
    pending.catch(() => {
      connected = undefined;
    });
    return pending;
  };
  const redis = async (): Promise<RedisStreamClient> =>
    (await connection()).client;
  const prefix = options.keyPrefix ?? "bs:stream";
  const defaultTtl = ttlSeconds(options.ttl ?? DAY);
  const wakes = "url" in options || options.subscriber !== undefined;
  const pollMs = options.pollMs ?? (wakes ? 2000 : 250);
  const batch = options.batch ?? 1000;
  const meta = (id: string): string => `${prefix}:${id}:meta`;
  const list = (id: string): string => `${prefix}:${id}:chunks`;
  const channel = (id: string): string => `${prefix}:${id}`;

  const state = async (
    id: string,
  ): Promise<Record<string, string> | undefined> => {
    const value = await (await redis()).hGetAll(meta(id));
    if (!isRecord(value) || text(value["created"]) === undefined)
      return undefined;
    const fields: Record<string, string> = {};
    for (const [key, entry] of Object.entries(value)) {
      const field = text(entry);
      if (field !== undefined) fields[key] = field;
    }
    return fields;
  };
  const length = async (id: string): Promise<number> =>
    Number(await (await redis()).lLen(list(id)));
  const missing = (id: string) =>
    dbError("not_found", `stream ${id} does not exist`, {
      hint: "STREAM_NOT_FOUND",
    });
  const attempt = <T>(run: () => Promise<T>): AsyncResult<T> =>
    AsyncResult.from(async () => ok(await run()));

  const status = (id: string): AsyncResult<StreamStatus | undefined> =>
    attempt(async () => {
      const fields = await state(id);
      if (!fields) return;
      return {
        next: await length(id),
        closed: fields["closed"] !== undefined,
        cancelled: fields["cancelled"] !== undefined,
      };
    });

  const mark = (id: string, field: "closed" | "cancelled") =>
    attempt(async () => {
      const fields = await state(id);
      if (!fields || fields[field] !== undefined) return false;
      if (field === "cancelled" && fields["closed"] !== undefined) return false;
      const client = await redis();
      await client.hSet(meta(id), field, new Date().toISOString());
      await client.publish(
        channel(id),
        field === "closed" ? "close" : "cancel",
      );
      // Writers on other instances subscribe here to stop generating.
      if (field === "cancelled")
        await client.publish(`${channel(id)}:cancel`, "cancel");
      return true;
    });

  return {
    apiVersion: 1,
    name: "redis",
    open: (id, open = {}) => {
      const ttl = open.ttl === undefined ? defaultTtl : ttlSeconds(open.ttl);
      if (ttl === undefined) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            `ttl must be seconds or "<n> seconds|minutes|hours|days"`,
          ),
        );
      }
      return attempt(async () => {
        const client = await redis();
        const created = await client.hSetNX(
          meta(id),
          "created",
          new Date().toISOString(),
        );
        if (created !== true && Number(created) !== 1) return false;
        await client.hSet(meta(id), "kind", open.kind ?? "default");
        if (open.owner !== undefined)
          await client.hSet(meta(id), "owner", open.owner);
        if (open.tenant !== undefined)
          await client.hSet(meta(id), "tenant", open.tenant);
        await client.hSet(meta(id), "ttl", String(ttl));
        await client.expire(meta(id), ttl);
        return true;
      });
    },
    append: (id, fromIdx, chunks) =>
      AsyncResult.from(async () => {
        const fields = await state(id);
        if (!fields) return err(missing(id));
        if (fields["closed"] !== undefined) {
          return err(
            dbError("raised", `stream ${id} is closed`, {
              hint: "STREAM_CLOSED",
            }),
          );
        }
        const stored = await length(id);
        if (fromIdx < 0 || fromIdx > stored) {
          return err(
            dbError(
              "raised",
              `stream ${id} is at chunk ${String(stored)}, not ${String(fromIdx)}`,
              {
                hint: "STREAM_GAP",
              },
            ),
          );
        }
        const fresh = chunks.slice(stored - fromIdx);
        if (fresh.length > 0) {
          const client = await redis();
          await client.rPush(list(id), [...fresh]);
          await client.expire(list(id), Number(fields["ttl"] ?? DAY));
          await client.publish(channel(id), "append");
        }
        return ok({
          next: Math.max(stored, fromIdx + chunks.length),
          cancelled: fields["cancelled"] !== undefined,
        });
      }),
    read: (id, fromIdx = 0, read = {}) =>
      pollingRead({
        from: fromIdx,
        pollMs,
        signal: read.signal,
        ...(wakes
          ? {
              subscribe: (wake: () => void) => {
                const listener = (): void => {
                  wake();
                };
                const joined = connection().then(async ({ subscriber }) => {
                  await subscriber?.subscribe(channel(id), listener);
                  return subscriber;
                });
                return () => {
                  void joined
                    .then((subscriber) =>
                      subscriber?.unsubscribe(channel(id), listener),
                    )
                    .catch(() => {});
                };
              },
            }
          : {}),
        fetch: (from) =>
          attempt(async (): Promise<StreamPage> => {
            const fields = await state(id);
            if (!fields) return { chunks: [], next: from, done: true };
            const value = await (
              await redis()
            ).lRange(list(id), from, from + batch - 1);
            const chunks = Array.isArray(value) ? value.map(String) : [];
            const next = from + chunks.length;
            return {
              chunks,
              next,
              done:
                fields["closed"] !== undefined && next >= (await length(id)),
            };
          }),
      }),
    status,
    isCancelled: (id) => status(id).map((value) => value?.cancelled === true),
    close: (id) => mark(id, "closed"),
    cancel: (id) => mark(id, "cancelled"),
    purge: () => AsyncResult.ok(0),
  };
}
