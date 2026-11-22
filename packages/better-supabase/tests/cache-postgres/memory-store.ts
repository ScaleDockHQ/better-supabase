import type {
  PostgresCacheStore,
  StoredCacheEntry,
  TagState,
} from "../../src/cache-postgres/store.ts";

import { ok } from "../../src/core/result.ts";

/** A `PostgresCacheStore` over maps, with the semantics of the real tables. */
export function memoryStore(): PostgresCacheStore & {
  readonly entries: Map<string, StoredCacheEntry>;
} {
  const entries = new Map<string, StoredCacheEntry>();
  const states = new Map<string, TagState>();

  return {
    entries,
    get: (key) => Promise.resolve(ok(entries.get(key))),
    set: (entry) => {
      entries.set(entry.key, entry);

      return Promise.resolve(ok(true as const));
    },
    deletePath: (path) => {
      for (const [key, entry] of entries) {
        if (entry.path === path) {
          entries.delete(key);
        }
      }

      return Promise.resolve(ok(true as const));
    },
    tagStates: (tags) =>
      Promise.resolve(
        ok(
          new Map(
            tags.flatMap((tag) => {
              const state = states.get(tag);

              return state ? [[tag, state] as const] : [];
            }),
          ),
        ),
      ),
    markTags: (tags, options = {}) => {
      const now = options.now ?? Date.now();

      for (const tag of tags) {
        const before = states.get(tag);

        states.set(tag, {
          staleAt: now,
          expiredAt: options.staleOnly
            ? (before?.expiredAt ?? 0)
            : options.expireSeconds === undefined
              ? now
              : now + options.expireSeconds * 1000,
        });
      }

      return Promise.resolve(ok(true as const));
    },
    prune: () => Promise.resolve(ok(true as const)),
  };
}
