import type { CacheAdapter } from "./cache.ts";

import { cacheTagsOf } from "./tags.ts";

/** Most tags a purge call carries, from the Vercel limit on a bulk call. */
const PURGE_BATCH = 16;

/** Most UTF-8 bytes a Vercel cache tag may have. */
const MAX_TAG_BYTES = 256;

/** Most tags Vercel keeps on one cached response. */
const MAX_TAGS_PER_RESPONSE = 128;

const encoder = new TextEncoder();

/** What a tag keeps as it is: no comma, no URL delimiter, no `~`. */
const UNSAFE = /[^\w:@.*/=-]/gu;

function escapeChar(char: string): string {
  return [...encoder.encode(char)]
    .map((byte) => `~${byte.toString(16).padStart(2, "0")}`)
    .join("");
}

/**
 * Makes a `bsb:` tag safe for Vercel: a comma splits a tag in two (composite
 * keys join their parts with one), and the Runtime Cache puts tags in a URL
 * query unescaped. Each other character becomes `~` and the hex of its UTF-8
 * bytes, so two tags never collide. A tag over 256 bytes returns `undefined`:
 * the entry keeps its table tag, which a write expires too.
 */
export function encodeCacheTag(tag: string): string | undefined {
  const encoded = tag.replaceAll(UNSAFE, escapeChar);

  return encoder.encode(encoded).length > MAX_TAG_BYTES ? undefined : encoded;
}

/** The encoded tags, once each, without the ones Vercel can't hold. */
function encodedTags(tags: readonly string[]): string[] {
  return [...new Set(tags.flatMap((tag) => encodeCacheTag(tag) ?? []))];
}

function inBatches(tags: readonly string[]): string[][] {
  const batches: string[][] = [];

  for (let index = 0; index < tags.length; index += PURGE_BATCH) {
    batches.push(tags.slice(index, index + PURGE_BATCH));
  }

  return batches;
}

/**
 * The part of the Vercel Runtime Cache that `vercelRuntimeCacheAdapter` calls,
 * typed structurally; `getCache()` from `@vercel/functions` returns it.
 */
export interface VercelRuntimeCacheTags {
  get(key: string): Promise<unknown>;
  set(
    key: string,
    value: unknown,
    options?: { name?: string; tags?: string[]; ttl?: number },
  ): Promise<void>;
  expireTag(tag: string | string[]): Promise<void>;
  /** Removes one entry; `@vercel/functions` has it, a hand-written stub may not. */
  delete?(key: string): Promise<void>;
}

export interface VercelRuntimeCacheAdapterOptions {
  /** The cache namespace the entries go in. Default: `better-supabase-data`. */
  readonly namespace?: string;
}

/** What `set` takes: `tags` are `bsb:` tags from `tagFor`, not yet encoded. */
export interface RuntimeCacheEntryOptions {
  /** Seconds the entry lives. */
  readonly ttl?: number;
  /** Tags such as `tagFor("orders")` and `tagFor("orders", id)`. */
  readonly tags?: readonly string[];
  /** A name for the entry in Vercel's observability. */
  readonly name?: string;
}

export interface VercelRuntimeCacheAdapter extends CacheAdapter {
  readonly name: "vercel-runtime-cache";
  get(key: string): Promise<unknown>;
  /** Stores a value under `key` with its tags encoded for Vercel. */
  set(
    key: string,
    value: unknown,
    options?: RuntimeCacheEntryOptions,
  ): Promise<void>;
  /** Removes the entry under `key`; a cache without `delete` keeps it. */
  delete(key: string): Promise<void>;
  /** Expires `bsb:` tags, encoded, in calls of 16 tags. */
  expireTags(tags: readonly string[]): Promise<void>;
}

/**
 * A `CacheAdapter` on the Vercel Runtime Cache. A mutation calls `expireTag`
 * with the tags of its table, tenant and rows; entries you stored with `set`
 * and the same tags go stale on the next read. Pass `getCache` from
 * `@vercel/functions`; it is called on first use, so the adapter can be created
 * at module scope.
 *
 * ```ts
 * betterSupabase.cache(vercelRuntimeCacheAdapter(getCache));
 * ```
 */
export function vercelRuntimeCacheAdapter(
  getCache: (options?: { namespace?: string }) => VercelRuntimeCacheTags,
  options: VercelRuntimeCacheAdapterOptions = {},
): VercelRuntimeCacheAdapter {
  let cache: VercelRuntimeCacheTags | undefined;

  const open = (): VercelRuntimeCacheTags =>
    (cache ??= getCache({
      namespace: options.namespace ?? "better-supabase-data",
    }));

  return {
    name: "vercel-runtime-cache",
    get: async (key) => open().get(key),
    set: async (key, value, entry = {}) => {
      const tags = encodedTags(entry.tags ?? []);

      return open().set(key, value, {
        ...(entry.ttl === undefined ? {} : { ttl: entry.ttl }),
        ...(entry.name === undefined ? {} : { name: entry.name }),
        ...(tags.length === 0 ? {} : { tags }),
      });
    },
    delete: async (key) => {
      await open().delete?.(key);
    },
    expireTags: async (tags) => {
      await Promise.all(
        inBatches(encodedTags(tags)).map((batch) => open().expireTag(batch)),
      );
    },
    invalidate: async (target) => {
      await Promise.all(
        inBatches(encodedTags(cacheTagsOf(target))).map((batch) =>
          open().expireTag(batch),
        ),
      );
    },
  };
}

/**
 * The part of `@vercel/functions` that `vercelCdnCache` calls: `addCacheTag`
 * tags the response being built and `invalidateByTag` marks every cached
 * response with a tag stale.
 */
export interface VercelCdnFunctions {
  readonly addCacheTag: (tag: string | string[]) => Promise<void>;
  readonly invalidateByTag: (tag: string | string[]) => Promise<void>;
}

export interface VercelCdnCache extends CacheAdapter {
  readonly name: "vercel-cdn";
  /**
   * Tags the current response (`addCacheTag`) with `bsb:` tags from `tagFor`,
   * encoded for Vercel and capped at the 128 tags a response keeps.
   */
  tag(...tags: readonly string[]): Promise<void>;
}

/**
 * A `CacheAdapter` on Vercel's CDN, for frameworks other than Next.js (Next.js
 * `cacheTag` already tags the CDN entry). A mutation calls `invalidateByTag`:
 * the next request serves the stale response and refreshes it in the
 * background. Vercel purges a tag in the CDN, the Runtime Cache and the Data
 * Cache, so one adapter covers all three. Outside a Vercel function, both
 * functions do nothing.
 *
 * ```ts
 * import { addCacheTag, invalidateByTag } from "@vercel/functions";
 *
 * const cdn = vercelCdnCache({ addCacheTag, invalidateByTag });
 * betterSupabase.cache(cdn);
 * // In a route: await cdn.tag(tagFor("orders"));
 * ```
 */
export function vercelCdnCache(sdk: VercelCdnFunctions): VercelCdnCache {
  return {
    name: "vercel-cdn",
    tag: async (...tags) => {
      const encoded = encodedTags(tags).slice(0, MAX_TAGS_PER_RESPONSE);

      if (encoded.length > 0) {
        await sdk.addCacheTag(encoded);
      }
    },
    invalidate: async (target) => {
      const tags = encodedTags(cacheTagsOf(target));

      await Promise.all(
        inBatches(tags).map((batch) => sdk.invalidateByTag(batch)),
      );
    },
  };
}
