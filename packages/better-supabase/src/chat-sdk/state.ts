import type { Lock, QueueEntry, SerializedMessage, StateAdapter } from "chat";

import { Message } from "chat";

import type { BlockTransport } from "../core/block-transport.ts";
import type { ErrorMapper } from "../core/errors.ts";

import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  isRecord,
  randomToken,
} from "../blocks/shared.ts";

export interface SupabaseStateOptions {
  /** `sqlTransport(postgres.asService())` or `rpcTransport` with the service role key. */
  readonly transport: BlockTransport;
  /** The schema of the `chat-sdk-state` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Separates bots that share the tables. Defaults to `chat-sdk`. */
  readonly keyPrefix?: string;
}

/** The `StateAdapter` with the prefix it writes under, for tests and sweeps. */
export interface SupabaseState extends StateAdapter {
  readonly keyPrefix: string;
  /** Deletes expired rows, at most `batch` of each kind; returns how many went. */
  purge(options?: { readonly batch?: number }): Promise<number>;
}

// Every value is stored as `{ v: value }`: a bare string or array would not
// reach a jsonb parameter intact over every transport.
const wrap = (value: unknown): { readonly v: unknown } => ({
  v: value === undefined ? null : value,
});
const unwrap = (stored: unknown): unknown =>
  isRecord(stored) && "v" in stored ? stored["v"] : stored;

function lockOf(value: unknown): Lock | null {
  if (!isRecord(value)) return null;
  const expires = value["expires_at"];
  return {
    threadId: String(value["thread_id"]),
    token: String(value["token"]),
    expiresAt:
      typeof expires === "string" || expires instanceof Date
        ? new Date(expires).getTime()
        : Date.now(),
  };
}

const isSerializedMessage = (value: unknown): value is SerializedMessage =>
  isRecord(value) && value["_type"] === "chat:Message";

function queueEntryOf(value: unknown): QueueEntry | null {
  if (!isRecord(value)) return null;
  const message: unknown = value["message"];
  if (!isSerializedMessage(message)) return null;
  return {
    enqueuedAt: Number(value["enqueuedAt"]),
    expiresAt: Number(value["expiresAt"]),
    message: Message.fromJSON(message),
  };
}

const ms = (value: number | undefined): number | undefined =>
  value === undefined || value <= 0 ? undefined : Math.ceil(value);

/**
 * A Chat SDK `StateAdapter` on the `chat-sdk-state` SQL module: thread
 * subscriptions, locks, the cache, lists and the per-thread queue in
 * Postgres, so a bot needs no Redis. Service role only.
 */
export function createSupabaseState(
  options: SupabaseStateOptions,
): SupabaseState {
  const prefix = options.keyPrefix ?? "chat-sdk";
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );
  const run = <T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T,
  ): Promise<T> => call(fn, { prefix, ...args }, then).orThrow();

  return {
    keyPrefix: prefix,
    connect: () => Promise.resolve(),
    disconnect: () => Promise.resolve(),
    subscribe: (threadId) =>
      run("chat_state_subscribe", { thread_id: threadId }, () => undefined),
    unsubscribe: (threadId) =>
      run("chat_state_unsubscribe", { thread_id: threadId }, () => undefined),
    isSubscribed: (threadId) =>
      run(
        "chat_state_is_subscribed",
        { thread_id: threadId },
        (value) => value === true,
      ),
    acquireLock: (threadId, ttlMs) =>
      run(
        "chat_state_acquire_lock",
        {
          thread_id: threadId,
          token: randomToken(),
          ttl_ms: Math.max(1, Math.ceil(ttlMs)),
        },
        lockOf,
      ),
    extendLock: (lock, ttlMs) =>
      run(
        "chat_state_extend_lock",
        {
          thread_id: lock.threadId,
          token: lock.token,
          ttl_ms: Math.max(1, Math.ceil(ttlMs)),
        },
        (value) => value === true,
      ),
    releaseLock: (lock) =>
      run(
        "chat_state_release_lock",
        { thread_id: lock.threadId, token: lock.token },
        () => undefined,
      ),
    forceReleaseLock: (threadId) =>
      run(
        "chat_state_force_release_lock",
        { thread_id: threadId },
        () => undefined,
      ),
    get: <T>(key: string) =>
      run("chat_state_get", { key }, (value) => {
        if (!isRecord(value)) return null;
        // SAFETY: the caller names the type it stored under this key.
        return unwrap(value["value"]) as T;
      }),
    set: (key, value, ttlMs) =>
      run(
        "chat_state_set",
        { key, value: wrap(value), ttl_ms: ms(ttlMs) },
        () => undefined,
      ),
    setIfNotExists: (key, value, ttlMs) =>
      run(
        "chat_state_set_if_not_exists",
        { key, value: wrap(value), ttl_ms: ms(ttlMs) },
        (result) => result === true,
      ),
    delete: (key) => run("chat_state_delete", { key }, () => undefined),
    appendToList: (key, value, listOptions = {}) =>
      run(
        "chat_state_append_to_list",
        {
          key,
          value: wrap(value),
          max_length: ms(listOptions.maxLength),
          ttl_ms: ms(listOptions.ttlMs),
        },
        () => undefined,
      ),
    getList: <T>(key: string) =>
      run("chat_state_get_list", { key }, (value) => {
        if (!Array.isArray(value)) return [];
        // SAFETY: the caller names the type it appended under this key.
        return value.map(unwrap) as T[];
      }),
    enqueue: (threadId, entry, maxSize) =>
      run(
        "chat_state_enqueue",
        {
          thread_id: threadId,
          entry: {
            enqueuedAt: entry.enqueuedAt,
            expiresAt: entry.expiresAt,
            message: entry.message.toJSON(),
          },
          expires_at: new Date(entry.expiresAt).toISOString(),
          max_size: ms(maxSize),
        },
        Number,
      ),
    dequeue: (threadId) =>
      run("chat_state_dequeue", { thread_id: threadId }, queueEntryOf),
    queueDepth: (threadId) =>
      run("chat_state_queue_depth", { thread_id: threadId }, Number),
    purge: (purgeOptions = {}) =>
      call("purge_chat_state", { batch: purgeOptions.batch }, Number).orThrow(),
  };
}
