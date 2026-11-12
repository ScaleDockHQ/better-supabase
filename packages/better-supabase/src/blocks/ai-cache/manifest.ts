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
    entities: {
      ai_cache: { mutability: "append-only", emits: { create: false } },
    },
    description:
      "Model responses cached by a key the application derives from the request, with a TTL capped by maxTtl, hit counts and a purge of expired entries; only the service role reads and writes it.",
  });
