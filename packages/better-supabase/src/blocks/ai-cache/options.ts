import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.ai-cache.options`. */
export type AiCacheSqlOptions = {
  readonly maxTtl?: number;
  readonly maxBytes?: number;
};

export const aiCacheSqlOptions: BlockOptionsSchema<AiCacheSqlOptions> =
  blockOptions<AiCacheSqlOptions>({
    maxTtl: option.number(),
    maxBytes: option.number(),
  });
