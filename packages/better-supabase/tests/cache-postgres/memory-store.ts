import type {
  PostgresCacheStore,
  StoredCacheEntry,
  TagState,
} from "../../src/cache-postgres/store.ts";

import { ok } from "../../src/core/result.ts";

const between = (at: number, since: number, now: number): boolean =>
  at > since && at <= now;

/**
 * A `PostgresCacheStore` over maps, with the semantics of the real tables and
 * functions: every tag column only moves forward.
 */
export function memoryStore(): PostgresCacheStore & {
  readonly entries: Map<string, StoredCacheEntry>;
} {
  const entries = new Map<string, StoredCacheEntry>();
  const states = new Map<string, Required<TagState>>();

  return {
    entries,
    get: (key) => Promise.resolve(ok(entries.get(key))),
    lookup: (key, softTags = [], now = Date.now()) => {
      const entry = entries.get(key);

      if (!entry || entry.expiresAt <= now) {
        return Promise.resolve(ok(undefined));
      }

      const tagged = [...entry.tags, ...softTags].flatMap((tag) => {
        const state = states.get(tag);

        return state ? [state] : [];
      });

      const expired = tagged.some(
        (state) =>
          between(state.expiredAt, entry.storedAt, now) ||
          between(state.expireAfter, entry.storedAt, now),
      );

      return Promise.resolve(
        ok(
          expired
            ? undefined
            : {
                entry,
                stale: tagged.some((state) => state.staleAt > entry.storedAt),
              },
        ),
      );
    },
    set: (entry) => {
      entries.set(entry.key, entry);

      return Promise.resolve(ok(true as const));
    },
    delete: (key) => {
      entries.delete(key);

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
        const before = states.get(tag) ?? {
          staleAt: 0,
          expiredAt: 0,
          expireAfter: 0,
        };

        states.set(tag, {
          staleAt: Math.max(before.staleAt, now),
          expiredAt:
            options.staleOnly || options.expireSeconds !== undefined
              ? before.expiredAt
              : Math.max(before.expiredAt, now),
          expireAfter:
            !options.staleOnly && options.expireSeconds !== undefined
              ? Math.max(before.expireAfter, now + options.expireSeconds * 1000)
              : before.expireAfter,
        });
      }

      return Promise.resolve(ok(true as const));
    },
    prune: () => Promise.resolve(ok(true as const)),
  };
}
