// Counts what Next.js asks of the `"use cache: remote"` handler: reads (hits and
// misses), writes with their bytes, and tag updates with the tag names. The
// counters live on `globalThis` so the testing route in the app bundle reads
// the ones the handler module (loaded by Next.js, not bundled) writes. Node
// loads it with type stripping, so it stays erasable syntax.
import type {
  CacheEntry,
  CacheHandler,
} from "next/dist/server/lib/cache-handlers/types";

export interface RemoteCacheCounters {
  gets: number;
  hits: number;
  sets: number;
  /** Bytes the handler was asked to store. */
  bytesSet: number;
  /** Bytes of the entries the handler returned. */
  bytesRead: number;
  updateTags: number;
  /** Every tag `updateTags` received, in call order. */
  expiredTags: string[];
}

const KEY = "bsbRemoteCacheCounters";

const fresh = (): RemoteCacheCounters => ({
  gets: 0,
  hits: 0,
  sets: 0,
  bytesSet: 0,
  bytesRead: 0,
  updateTags: 0,
  expiredTags: [],
});

type Holder = typeof globalThis & { [KEY]?: RemoteCacheCounters };

/** The counters of this process. */
function remoteCacheCounters(): RemoteCacheCounters {
  const holder: Holder = globalThis;

  holder[KEY] ??= fresh();

  return holder[KEY];
}

/** Counts the bytes of `stream` and returns a stream with the same bytes. */
function counted(
  stream: ReadableStream<Uint8Array>,
  add: (bytes: number) => void,
): ReadableStream<Uint8Array> {
  return stream.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        add(chunk.byteLength);
        controller.enqueue(chunk);
      },
    }),
  );
}

/** `handler`, with every call counted in `remoteCacheCounters()`. */
export function countingCacheHandler(handler: CacheHandler): CacheHandler {
  return {
    async get(cacheKey, softTags) {
      const counters = remoteCacheCounters();

      counters.gets += 1;

      const found = await handler.get(cacheKey, softTags);

      if (!found) {
        return found;
      }

      counters.hits += 1;

      return {
        ...found,
        value: counted(found.value, (bytes) => {
          remoteCacheCounters().bytesRead += bytes;
        }),
      };
    },

    set(cacheKey, pendingEntry) {
      remoteCacheCounters().sets += 1;

      const wrapped: Promise<CacheEntry> = pendingEntry.then((entry) => ({
        ...entry,
        value: counted(entry.value, (bytes) => {
          remoteCacheCounters().bytesSet += bytes;
        }),
      }));

      return handler.set(cacheKey, wrapped);
    },

    refreshTags: () => handler.refreshTags(),

    getExpiration: (tags) => handler.getExpiration(tags),

    updateTags(tags, durations) {
      const counters = remoteCacheCounters();

      counters.updateTags += 1;
      counters.expiredTags.push(...tags);

      return handler.updateTags(tags, durations);
    },
  };
}
