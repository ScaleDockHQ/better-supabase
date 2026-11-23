import type { KeptLease, KeptStore } from "../core/kept-cache.ts";
import type { PostgresCacheSource, PostgresCacheTables } from "./store.ts";

import { storeOf } from "./store.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

type Store = ReturnType<typeof storeOf>;

const leaseOf = (store: Store): KeptLease => ({
  async lease(key, holder, ttlMs) {
    const leased = await store.lease(key, holder, ttlMs);

    if (!leased.ok) {
      throw new Error(leased.error.message);
    }

    return leased.data;
  },
  async release(key, holder) {
    const released = await store.release(key, holder);

    if (!released.ok) {
      throw new Error(released.error.message);
    }
  },
});

/**
 * The fill lease of `postgresKeptStore` without its entries, for a store that
 * has no set-if-absent. Postgres takes the lease in one statement, so exactly
 * one instance fills a missing key while the entries stay in the Runtime
 * Cache:
 *
 * ```ts
 * vercelRuntimeCacheAdapter(getCache, {
 *   lease: postgresKeptLease({ client }),
 * });
 * ```
 */
export function postgresKeptLease(
  options: PostgresCacheTables & PostgresCacheSource,
): KeptLease {
  return leaseOf(storeOf(options));
}

/**
 * A `KeptStore` for `bsb.kept()` in the tables of `postgresCacheSql()`, next to
 * the Next.js handler's entries. A write expires its entries on every instance.
 * A failed call throws, and `bsb.kept()` then reads through.
 */
export function postgresKeptStore(
  options: PostgresCacheTables & PostgresCacheSource,
): KeptStore {
  const store = storeOf(options);

  return {
    async get(key) {
      const found = await store.lookup(key);

      if (!found.ok) {
        throw new Error(found.error.message);
      }

      const entry = found.data?.entry;

      const value: unknown = entry
        ? JSON.parse(decoder.decode(entry.value))
        : undefined;

      return value;
    },
    async set(key, value, setOptions) {
      const now = Date.now();

      const written = await store.set({
        key,
        value: encoder.encode(JSON.stringify(value)),
        tags: setOptions.tags,
        storedAt: now,
        expiresAt: now + setOptions.ttl * 1000,
        meta: { kind: "kept" },
      });

      if (!written.ok) {
        throw new Error(written.error.message);
      }
    },
    async expireTags(tags) {
      const marked = await store.markTags(tags);

      if (!marked.ok) {
        throw new Error(marked.error.message);
      }
    },
    async delete(key) {
      const deleted = await store.delete(key);

      if (!deleted.ok) {
        throw new Error(deleted.error.message);
      }
    },
    ...leaseOf(store),
  };
}
