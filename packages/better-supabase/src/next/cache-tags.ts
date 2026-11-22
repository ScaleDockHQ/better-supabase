import { cacheTag } from "next/cache.js";

/**
 * Next.js keeps at most 128 tags from one `cacheTag()` call and drops the rest
 * with a warning, so a long list goes in as several calls.
 */
const MAX_TAGS_PER_CALL = 128;

/** Tags the current `'use cache'` scope without losing any past the 128th. */
export function applyCacheTags(tags: Iterable<string>): void {
  const list = [...tags];

  for (let from = 0; from < list.length; from += MAX_TAGS_PER_CALL) {
    cacheTag(...list.slice(from, from + MAX_TAGS_PER_CALL));
  }
}
