import type { DbError } from "../core/errors.ts";
import type { PostgresCacheSource, PostgresCacheTables } from "./store.ts";

import { DbException } from "../core/errors.ts";
import { storeOf } from "./store.ts";

/** What `get` returns and `set` receives; Next.js's `CacheEntry`, typed here. */
export interface NextCacheEntry {
  value: ReadableStream<Uint8Array>;
  tags: string[];
  stale: number;
  timestamp: number;
  expire: number;
  revalidate: number;
}

/**
 * Next.js's `CacheHandler` for `cacheHandlers` in `next.config`, typed
 * structurally so the entry imports nothing from `next`.
 */
export interface NextCacheHandler {
  get(
    cacheKey: string,
    softTags: string[],
  ): Promise<NextCacheEntry | undefined>;
  set(cacheKey: string, pendingEntry: Promise<NextCacheEntry>): Promise<void>;
  refreshTags(): Promise<void>;
  getExpiration(tags: string[]): Promise<number>;
  updateTags(tags: string[], durations?: { expire?: number }): Promise<void>;
}

export type PostgresCacheHandlerOptions = PostgresCacheTables &
  PostgresCacheSource & {
    /**
     * Called with a store error. The handler treats it as a miss (read) or a
     * skipped write, so a database outage slows the app and never breaks it.
     */
    readonly onError?: ((error: DbError) => void) | undefined;
    /** Next.js dev server: an entry lives until `expire`, not `revalidate`. */
    readonly development?: boolean | undefined;
  };

function streamOf(bytes: Uint8Array<ArrayBuffer>): ReadableStream<Uint8Array> {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

async function bytesOf(
  stream: ReadableStream<Uint8Array>,
): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/**
 * A Next.js `cacheHandlers` handler that keeps `'use cache'` entries and tag
 * states in Postgres (`postgresCacheSql()` creates the tables), so every
 * instance serves what another one rendered and `updateTag` or `revalidateTag`
 * takes effect on all of them. Tags are read in chunks of 128, the same size
 * `applyCacheTags` writes them in.
 *
 * ```ts
 * // cache-handlers/postgres.ts
 * export default postgresCacheHandler({ client: serviceRoleClient });
 * ```
 */
export function postgresCacheHandler(
  options: PostgresCacheHandlerOptions,
): NextCacheHandler {
  const store = storeOf(options);

  const dev = options.development ?? false;
  const pending = new Map<string, Promise<void>>();

  const report = (error: DbError): void => {
    options.onError?.(error);
  };

  return {
    async get(cacheKey, softTags) {
      await pending.get(cacheKey);

      const found = await store.lookup(cacheKey, softTags);

      if (!found.ok) {
        report(found.error);

        return;
      }

      if (!found.data) {
        return;
      }

      const { entry: row, stale: isStale } = found.data;

      // SAFETY: `set` below wrote `meta` with these numbers.
      const { stale, expire, revalidate } = row.meta as {
        stale: number;
        expire: number;
        revalidate: number;
      };

      return {
        value: streamOf(row.value),
        tags: [...row.tags],
        stale,
        timestamp: row.storedAt,
        expire,
        revalidate: isStale ? -1 : revalidate,
      };
    },

    async set(cacheKey, pendingEntry) {
      let done = () => {};

      pending.set(
        cacheKey,
        new Promise<void>((resolve) => {
          done = resolve;
        }),
      );

      try {
        const entry = await pendingEntry;

        // A production `expire: 0` entry is regenerated on every read.
        if (!dev && entry.expire === 0) {
          return;
        }

        const written = await store.set({
          key: cacheKey,
          value: await bytesOf(entry.value),
          tags: entry.tags,
          storedAt: entry.timestamp,
          expiresAt: entry.timestamp + Math.max(entry.expire, 0) * 1000,
          meta: {
            stale: entry.stale,
            expire: entry.expire,
            revalidate: entry.revalidate,
          },
        });

        if (!written.ok) {
          report(written.error);
        }
      } catch {
        // A failed or partial stream is a miss on the next read.
      } finally {
        done();
        pending.delete(cacheKey);
      }
    },

    refreshTags() {
      // Every read asks Postgres, so there is no local manifest to refresh.
      return Promise.resolve();
    },

    async getExpiration(tags) {
      const states = await store.tagStates(tags);

      if (!states.ok) {
        report(states.error);

        return 0;
      }

      return Math.max(
        0,
        ...[...states.data.values()].map((state) =>
          Math.max(state.expiredAt, state.expireAfter ?? 0),
        ),
      );
    },

    async updateTags(tags, durations) {
      const marked = await store.markTags(
        tags,
        durations === undefined
          ? {}
          : durations.expire === undefined
            ? { staleOnly: true }
            : { expireSeconds: durations.expire },
      );

      // A lost invalidation would serve stale data, so it is not swallowed.
      if (!marked.ok) {
        report(marked.error);

        throw new DbException(marked.error);
      }
    },
  };
}
