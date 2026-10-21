import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.search.options`. */
export type SearchSqlOptions = {
  readonly config?: string;
  readonly dimensions?: number;
};

export const searchSqlOptions: BlockOptionsSchema<SearchSqlOptions> =
  blockOptions<SearchSqlOptions>({
    config: option.string({ default: "simple" }),
    dimensions: option.number({ default: 0 }),
  });
