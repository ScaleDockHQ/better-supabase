import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createAiCache } from "./ai-cache.ts";
import { aiCacheSqlOptions } from "./options.ts";

/** The `ai-cache` block's manifest (ADR 0029). */
export const aiCacheBlock: BlockOf<"ai-cache", typeof createAiCache> =
  defineBlock({
    name: "ai-cache",
    sql: ["ai-cache"],
    options: { "ai-cache": aiCacheSqlOptions },
    create: createAiCache,
    category: "ai",
  });
