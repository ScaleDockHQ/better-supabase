import { cacheTag } from "next/cache.js";

import { chunkTags } from "../core/tag-chunks.ts";

/** Tags the current `'use cache'` scope without losing any past the 128th. */
export function applyCacheTags(tags: Iterable<string>): void {
  for (const chunk of chunkTags(tags)) {
    cacheTag(...chunk);
  }
}
