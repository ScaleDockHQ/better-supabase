import type { AuthzVersionCache } from "../core/authorizer.ts";

import {
  AUTHZ_EVENT,
  AUTHZ_TOPIC,
  authzUserTopic,
} from "../core/authz-topic.ts";

/** The broadcast message shape Realtime delivers for `realtime.send()`. */
interface BroadcastMessage {
  readonly payload?: unknown;
}

/** The part of a supabase-js `RealtimeChannel` the subscriber uses. */
export interface AuthzVersionChannel {
  on(
    type: "broadcast",
    filter: { readonly event: string },
    callback: (message: BroadcastMessage) => void,
  ): AuthzVersionChannel;
  subscribe(
    callback?: (status: string, error?: Error) => void,
  ): AuthzVersionChannel;
  unsubscribe(): Promise<unknown>;
}

/** The part of a supabase-js client the subscriber uses. */
export interface AuthzVersionClient {
  channel(
    topic: string,
    options: { readonly config: { readonly private: boolean } },
  ): AuthzVersionChannel;
}

export interface SubscribeAuthzVersionsOptions {
  /**
   * A service-role client. It reads the private channel without a
   * `realtime.messages` policy, so no user can listen.
   */
  readonly client: AuthzVersionClient;
  /**
   * The private channel the database trigger sends on. Defaults to
   * `AUTHZ_TOPIC`, the topic of the sessions module's `authzVersions` option. A
   * per-user `authz:<uid>` topic evicts that user when the payload names no
   * one.
   */
  readonly topic?: string;
  /** The broadcast event name the trigger uses. Defaults to `"changed"`. */
  readonly event?: string;
  /**
   * The payload key holding the user id whose authorization changed. Defaults
   * to `"user_id"`.
   */
  readonly userIdKey?: string;
  /** The app's module-scope cache; each message evicts one user. */
  readonly versions: AuthzVersionCache;
  /** Called for a malformed message, a failed eviction or a channel error. */
  readonly onError?: (error: Error) => void;
}

export interface AuthzVersionSubscription {
  /** Settles once the channel is subscribed; rejects when it can't join. */
  readonly ready: Promise<void>;
  /** Leaves the channel. A later `subscribeAuthzVersions` joins again. */
  close(): Promise<void>;
}

const USER_TOPIC_PREFIX = authzUserTopic("");

const subscriptions = new WeakMap<
  AuthzVersionCache,
  AuthzVersionSubscription
>();

function userIdOf(payload: unknown, key: string): string | undefined {
  if (typeof payload !== "object" || payload === null || !(key in payload)) {
    return undefined;
  }

  const value: unknown = Object.entries(payload).find(
    ([name]) => name === key,
  )?.[1];

  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/**
 * Evicts a user from `versions` whenever the database broadcasts that their
 * authorization changed, so the next check reads the new version. Call it once
 * from the module that creates `versions`; a second call with the same cache
 * returns the first subscription.
 *
 * ```ts
 * export const versions = createVersionCache();
 * subscribeAuthzVersions({ client: serviceClient, versions });
 * ```
 *
 * With the sessions module's `authzVersions` option the defaults match the
 * generated trigger. Pass `topic`, `event` and `userIdKey` for your own.
 *
 * ```ts
 * subscribeAuthzVersions({
 *   client: serviceClient,
 *   topic: "authz-versions",
 *   event: "changed",
 *   userIdKey: "user_id",
 *   versions,
 * });
 * ```
 */
export function subscribeAuthzVersions(
  options: SubscribeAuthzVersionsOptions,
): AuthzVersionSubscription {
  const existing = subscriptions.get(options.versions);

  if (existing) {
    return existing;
  }

  const topic = options.topic ?? AUTHZ_TOPIC;
  const event = options.event ?? AUTHZ_EVENT;
  const userIdKey = options.userIdKey ?? "user_id";

  const topicUser = topic.startsWith(USER_TOPIC_PREFIX)
    ? topic.slice(USER_TOPIC_PREFIX.length)
    : undefined;

  const report = (error: Error): void => {
    options.onError?.(error);
  };

  const channel = options.client.channel(topic, { config: { private: true } });

  channel.on("broadcast", { event }, (message) => {
    const userId = userIdOf(message.payload, userIdKey) ?? topicUser;

    if (userId === undefined) {
      report(
        new Error(
          `better-supabase: an ${event} message on ${topic} has no ${userIdKey}`,
        ),
      );

      return;
    }

    Promise.resolve(options.versions.evict(userId)).catch((cause: unknown) => {
      report(cause instanceof Error ? cause : new Error(String(cause)));
    });
  });

  const ready = new Promise<void>((resolve, reject) => {
    channel.subscribe((status, error) => {
      switch (status) {
        case "SUBSCRIBED": {
          resolve();
          break;
        }

        case "CHANNEL_ERROR":
        case "TIMED_OUT": {
          const failure =
            error ??
            new Error(`better-supabase: ${topic} ${status.toLowerCase()}`);

          report(failure);
          reject(failure);
          break;
        }

        default: {
          break;
        }
      }
    });
  });

  ready.catch(() => {
    subscriptions.delete(options.versions);
  });

  const subscription: AuthzVersionSubscription = {
    ready,
    async close() {
      subscriptions.delete(options.versions);
      await channel.unsubscribe();
    },
  };

  subscriptions.set(options.versions, subscription);

  return subscription;
}

/**
 * A shared store behind `createVersionCache`, such as Redis or Vercel Runtime
 * Cache.
 */
export interface VersionStore {
  get(userId: string): number | undefined | PromiseLike<number | undefined>;
  set(userId: string, version: number): void | PromiseLike<void>;
  delete(userId: string): void | PromiseLike<void>;
}

export interface CreateVersionCacheOptions {
  /** A shared store read on a local miss. Without one the cache is per instance. */
  readonly store?: VersionStore;
  /**
   * The longest a version stays trusted without a broadcast, in milliseconds.
   * It bounds how stale a check can be when an eviction message is lost.
   */
  readonly maxStaleMs: number;
  /**
   * The most users the in-process map keeps. The least recently used entry goes
   * first; the shared `store` still has it. Defaults to 10,000.
   */
  readonly maxEntries?: number;
}

const DEFAULT_MAX_ENTRIES = 10_000;

export interface VersionCache extends AuthzVersionCache {
  /** The cached version, or `undefined` when absent or older than `maxStaleMs`. */
  get(userId: string): Promise<number | undefined>;
  seed(userId: string, version: number): Promise<void>;
  evict(userId: string): Promise<void>;
}

interface VersionEntry {
  readonly version: number;
  readonly at: number;
}

/**
 * The module-scope `AuthzVersionCache` for `createServer({ versions })`. It
 * keeps the highest version seen per user, forgets it after `maxStaleMs`, and
 * reads and writes `store` so instances share what one of them learned.
 */
export function createVersionCache(
  options: CreateVersionCacheOptions,
): VersionCache {
  const local = new Map<string, VersionEntry>();
  const { store, maxStaleMs } = options;
  const maxEntries = Math.max(1, options.maxEntries ?? DEFAULT_MAX_ENTRIES);

  // Map keeps insertion order, so deleting before setting makes the last key
  // the most recently used and the first key the one to drop.
  const remember = (userId: string, entry: VersionEntry): void => {
    local.delete(userId);
    local.set(userId, entry);

    if (local.size > maxEntries) {
      const oldest = local.keys().next();

      if (!oldest.done) {
        local.delete(oldest.value);
      }
    }
  };

  return {
    async get(userId) {
      const hit = local.get(userId);

      if (hit && Date.now() - hit.at <= maxStaleMs) {
        remember(userId, hit);

        return hit.version;
      }

      local.delete(userId);

      const shared = await store?.get(userId);

      if (shared !== undefined) {
        remember(userId, { version: shared, at: Date.now() });
      }

      return shared;
    },
    async seed(userId, version) {
      const current = local.get(userId);

      const keep =
        current && Date.now() - current.at <= maxStaleMs
          ? Math.max(current.version, version)
          : version;

      remember(userId, { version: keep, at: Date.now() });
      await store?.set(userId, keep);
    },
    async evict(userId) {
      local.delete(userId);
      await store?.delete(userId);
    },
  };
}
