import type { CacheAdapter } from "./cache.ts";

import { encodeCacheTag } from "./cache-vercel.ts";
import { canonicalJson } from "./canonical-json.ts";
import { isRecord } from "./guards.ts";
import { cacheTagsOf } from "./tags.ts";

/** What a kept entry holds. Times are epoch milliseconds, `revalidate` seconds. */
export interface KeptEnvelope {
  readonly storedAt: number;
  readonly revalidate: number;
  /** The fill's value as JSON gives it back; absent for `undefined`. */
  readonly value?: unknown;
}

export interface KeptSetOptions {
  /** Seconds the store keeps the entry: the `expire` of its life. */
  readonly ttl: number;
  /** `bsb:` tags, not yet encoded for a store. */
  readonly tags: readonly string[];
}

/**
 * Where `bsb.kept()` keeps entries across requests and deploys.
 * `vercelRuntimeCacheAdapter`, `postgresKeptStore` and `memoryKeptStore` are
 * stores. `get` may return anything; a value that is not an envelope is a
 * miss.
 */
export interface KeptStore {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown, options: KeptSetOptions): Promise<void>;
  /** Expires every entry with one of `tags` (`bsb:` tags, not encoded). */
  expireTags(tags: readonly string[]): Promise<void>;
  /** Removes one entry; a store without it lets the entry expire. */
  delete?(key: string): Promise<void>;
  /**
   * Whether `holder` may fill `key` for the next `ttlMs` milliseconds, so one
   * instance fills a missing entry while the others wait for it. A store
   * without it lets every instance fill.
   */
  lease?(key: string, holder: string, ttlMs: number): Promise<boolean>;
  /** Ends `holder`'s lease on `key` once its fill is stored. */
  release?(key: string, holder: string): Promise<void>;
}

/** The limits of the Vercel Runtime Cache, applied to every store. */
export const KEPT_LIMITS: {
  readonly bytes: number;
  readonly tags: number;
  readonly tagBytes: number;
} = { bytes: 2 * 1024 * 1024, tags: 128, tagBytes: 256 };

/** Why a fill's value was not stored. */
export type KeptSkipReason =
  /** The entry is over `KEPT_LIMITS.bytes` as JSON. */
  | "size"
  /** More than `KEPT_LIMITS.tags` tags. */
  | "tags"
  /** A tag over `KEPT_LIMITS.tagBytes` once encoded. */
  | "tag"
  /** The value is not JSON (a `bigint`, a cycle). */
  | "value"
  /** The value is a failed `Result`, which is never stored. */
  | "error";

export interface KeptSkip {
  readonly name: string;
  readonly key: string;
  readonly reason: KeptSkipReason;
  readonly detail: string;
}

/** How a call was served. `wait` is a call that waited for another's fill. */
export type KeptOutcome = "hit" | "miss" | "stale" | "wait";

export interface KeptCall<T> {
  /** The name the app gave the function, for reports. */
  readonly name: string;
  /** From `keptKey`. */
  readonly key: string;
  readonly tags: readonly string[];
  /** Seconds the entry is fresh. */
  readonly revalidate: number;
  /** Seconds the store keeps it; a stale entry is served until then. */
  readonly expire: number;
  /** Runs the function as the caller. */
  readonly fill: () => Promise<T>;
  /**
   * Keeps a refresh alive after the response, such as `waitUntil`. Without it
   * the refresh runs unawaited.
   */
  readonly background?: ((pending: Promise<unknown>) => void) | undefined;
}

export interface KeptServed<T> {
  readonly value: T;
  readonly outcome: KeptOutcome;
  /** Milliseconds the fill took, when this call ran one. */
  readonly fillMs?: number;
}

export interface KeptCacheOptions {
  readonly store: KeptStore;
  /** Called for each value that was not stored. Default: nothing. */
  readonly onSkip?: ((skip: KeptSkip) => void) | undefined;
  /** Called when the store fails; the call then reads through. */
  readonly onError?: ((error: unknown) => void) | undefined;
  /**
   * Milliseconds a call waits for a fill another instance holds the lease for,
   * before it fills itself. Default: 250.
   */
  readonly wait?: number | undefined;
  /** Milliseconds a fill holds its lease at most. Default: 10 000. */
  readonly leaseMs?: number | undefined;
  readonly now?: () => number;
}

export interface KeptCache {
  readonly store: KeptStore;
  /** Serves `call` from the store, or fills and stores it. */
  serve<T>(call: KeptCall<T>): Promise<KeptServed<T>>;
  /** Expires the store's entries with one of `tags`. */
  expireTags(tags: readonly string[]): Promise<void>;
  /** For `betterSupabase.cache()`: a write expires its tables' entries. */
  readonly adapter: CacheAdapter;
}

const encoder = new TextEncoder();

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * The store key of a call: the SHA-256 of the name, the arguments as canonical
 * JSON, the share key and the version. The build id is never part of it, so an
 * entry outlives a deploy until `version` changes.
 */
export async function keptKey(parts: {
  readonly name: string;
  readonly args: readonly unknown[];
  readonly share: string;
  readonly version: string;
}): Promise<string> {
  const hash = await sha256(
    canonicalJson([parts.name, parts.args, parts.share, parts.version]),
  );

  return `kept:${hash}`;
}

/**
 * The default `version`: a hash of the generated schema's metadata, so a
 * migration that changes a table starts new entries.
 */
export async function keptVersionOf(meta: unknown): Promise<string> {
  return (await sha256(canonicalJson(meta))).slice(0, 16);
}

export function isKeptEnvelope(value: unknown): value is KeptEnvelope {
  return (
    isRecord(value) &&
    typeof value["storedAt"] === "number" &&
    typeof value["revalidate"] === "number"
  );
}

interface Refusal {
  readonly ok: false;
  readonly reason: KeptSkipReason;
  readonly detail: string;
}

/** Why `tags` can't go on an entry, or `undefined` when they can. */
function tagProblem(tags: readonly string[]): Refusal | undefined {
  if (tags.length > KEPT_LIMITS.tags) {
    return {
      ok: false,
      reason: "tags",
      detail: `${String(tags.length)} tags, over the limit of ${String(KEPT_LIMITS.tags)}`,
    };
  }

  const long = tags.find((tag) => encodeCacheTag(tag) === undefined);

  return long === undefined
    ? undefined
    : {
        ok: false,
        reason: "tag",
        detail: `the tag ${long.slice(0, 64)}... is over ${String(KEPT_LIMITS.tagBytes)} bytes once encoded`,
      };
}

/** The value as JSON gives it back, or why it can't be stored. */
function serialize(
  envelope: KeptEnvelope,
): { readonly ok: true; readonly text: string } | Refusal {
  if (isRecord(envelope.value) && envelope.value["ok"] === false) {
    return {
      ok: false,
      reason: "error",
      detail: "the function returned a failed Result",
    };
  }

  let text: string;

  try {
    text = JSON.stringify(envelope);
  } catch (cause) {
    return { ok: false, reason: "value", detail: String(cause) };
  }

  const bytes = encoder.encode(text).length;

  return bytes > KEPT_LIMITS.bytes
    ? {
        ok: false,
        reason: "size",
        detail: `${String(bytes)} bytes, over the limit of ${String(KEPT_LIMITS.bytes)}`,
      }
    : { ok: true, text };
}

/**
 * Entries that outlive a deploy: a hit returns the stored value, a stale entry
 * is served while one refresh runs, and a miss fills through `fill`. A store
 * error never fails a call; it reads through and reports to `onError`.
 */
const POLL_MS = 25;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

export function createKeptCache(options: KeptCacheOptions): KeptCache {
  const { store } = options;
  const now = options.now ?? Date.now;
  const wait = options.wait ?? 250;
  const leaseMs = options.leaseMs ?? 10_000;
  // One fill per key in this process; the lease covers the other instances.
  const flights = new Map<string, Promise<KeptServed<unknown>>>();
  const refreshing = new Set<string>();

  const report = (error: unknown): void => {
    options.onError?.(error);
  };

  const read = async (key: string): Promise<KeptEnvelope | undefined> => {
    try {
      const value = await store.get(key);

      return isKeptEnvelope(value) ? value : undefined;
    } catch (error) {
      report(error);

      return undefined;
    }
  };

  const fill = async <T>(call: KeptCall<T>): Promise<KeptServed<T>> => {
    const started = now();
    const value = await call.fill();
    const fillMs = now() - started;

    const envelope: KeptEnvelope = {
      storedAt: now(),
      revalidate: call.revalidate,
      ...(value === undefined ? {} : { value }),
    };

    const written = tagProblem(call.tags) ?? serialize(envelope);

    if (!written.ok) {
      options.onSkip?.({
        name: call.name,
        key: call.key,
        reason: written.reason,
        detail: written.detail,
      });

      return { value, outcome: "miss", fillMs };
    }

    // A store holds what JSON gives back, so a miss returns the same shape a
    // hit will.
    // SAFETY: `written.text` is `envelope` as JSON.
    const stored = JSON.parse(written.text) as KeptEnvelope;

    try {
      await store.set(call.key, stored, {
        ttl: Math.max(call.expire, call.revalidate),
        tags: call.tags,
      });
    } catch (error) {
      report(error);
    }

    // SAFETY: `stored.value` is the fill's value after a JSON round trip.
    return { value: stored.value as T, outcome: "miss", fillMs };
  };

  /** A holder when this call may fill, or `false` when another holds it. */
  const lease = async (key: string): Promise<string | true | false> => {
    if (!store.lease) {
      return true;
    }

    const holder = crypto.randomUUID();

    try {
      return (await store.lease(key, holder, leaseMs)) ? holder : false;
    } catch (error) {
      report(error);

      return true;
    }
  };

  const release = (key: string, holder: string | true): void => {
    if (holder !== true) {
      store.release?.(key, holder).catch(report);
    }
  };

  const fillLeased = async <T>(call: KeptCall<T>): Promise<KeptServed<T>> => {
    const holder = await lease(call.key);

    if (holder !== false) {
      try {
        return await fill(call);
      } finally {
        release(call.key, holder);
      }
    }

    for (let polled = 0; polled < wait; polled += POLL_MS) {
      await sleep(POLL_MS);

      const found = await read(call.key);

      if (found) {
        // SAFETY: the entry under this key was written from this call's fill.
        return { value: found.value as T, outcome: "wait" };
      }
    }

    return fill(call);
  };

  const once = async <T>(call: KeptCall<T>): Promise<KeptServed<T>> => {
    const running = flights.get(call.key);

    if (running) {
      // SAFETY: a flight under this key runs this call's fill.
      const served = (await running) as KeptServed<T>;

      return { value: served.value, outcome: "wait" };
    }

    const flight = fillLeased(call).finally(() => {
      flights.delete(call.key);
    });

    flights.set(call.key, flight);

    return flight;
  };

  const refresh = async <T>(call: KeptCall<T>): Promise<void> => {
    refreshing.add(call.key);

    try {
      const holder = await lease(call.key);

      if (holder === false) {
        return;
      }

      try {
        await fill(call);
      } finally {
        release(call.key, holder);
      }
    } finally {
      refreshing.delete(call.key);
    }
  };

  const expireTags = async (tags: readonly string[]): Promise<void> => {
    if (tags.length > 0) {
      await store.expireTags(tags);
    }
  };

  return {
    store,
    async serve<T>(call: KeptCall<T>): Promise<KeptServed<T>> {
      const found = await read(call.key);

      if (!found) {
        return once(call);
      }

      // SAFETY: the entry under this key was written from this call's fill.
      const value = found.value as T;

      if (now() < found.storedAt + found.revalidate * 1000) {
        return { value, outcome: "hit" };
      }

      if (!refreshing.has(call.key) && !flights.has(call.key)) {
        call.background?.(refresh(call).catch(report));
      }

      return { value, outcome: "stale" };
    },
    expireTags,
    adapter: {
      name: "kept",
      invalidate: (target) => expireTags(cacheTagsOf(target)),
    },
  };
}

interface MemoryEntry {
  readonly value: unknown;
  readonly tags: readonly string[];
  readonly storedAt: number;
  readonly expiresAt: number;
}

/**
 * A `KeptStore` in this process, for development and tests. Entries end with
 * the process, and each instance has its own.
 */
export function memoryKeptStore(
  options: { readonly now?: () => number } = {},
): KeptStore {
  const now = options.now ?? Date.now;
  const entries = new Map<string, MemoryEntry>();
  const expired = new Map<string, number>();
  const leases = new Map<string, { holder: string; until: number }>();

  return {
    get(key) {
      const entry = entries.get(key);
      const at = now();

      if (
        !entry ||
        at >= entry.expiresAt ||
        entry.tags.some((tag) => (expired.get(tag) ?? -1) >= entry.storedAt)
      ) {
        entries.delete(key);

        return Promise.resolve(undefined);
      }

      return Promise.resolve(entry.value);
    },
    set(key, value, setOptions) {
      const at = now();

      entries.set(key, {
        value,
        tags: [...setOptions.tags],
        storedAt: at,
        expiresAt: at + setOptions.ttl * 1000,
      });

      return Promise.resolve();
    },
    expireTags(tags) {
      const at = now();

      for (const tag of tags) {
        expired.set(tag, at);
      }

      return Promise.resolve();
    },
    delete(key) {
      entries.delete(key);

      return Promise.resolve();
    },
    lease(key, holder, ttlMs) {
      const at = now();
      const current = leases.get(key);

      if (current && current.until > at && current.holder !== holder) {
        return Promise.resolve(false);
      }

      leases.set(key, { holder, until: at + ttlMs });

      return Promise.resolve(true);
    },
    release(key, holder) {
      if (leases.get(key)?.holder === holder) {
        leases.delete(key);
      }

      return Promise.resolve();
    },
  };
}
