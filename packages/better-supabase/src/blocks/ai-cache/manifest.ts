import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAiCache } from "./ai-cache.ts";

/** The `ai-cache` block's manifest (ADR 0029). */
export const aiCacheBlock: BlockOf<"ai-cache", typeof createAiCache> =
  defineBlock({
    name: "ai-cache",
    sql: ["ai-cache"],
    options: {
      "ai-cache": optionKeys(["maxTtl", "maxBytes"]),
    },
    create: createAiCache,
    category: "ai",
  });
