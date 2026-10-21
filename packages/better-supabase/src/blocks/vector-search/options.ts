import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.vector-search.options`. */
export type VectorSearchSqlOptions = { readonly schema?: unknown };

export const vectorSearchSqlOptions: BlockOptionsSchema<VectorSearchSqlOptions> =
  blockOptions<VectorSearchSqlOptions>({ schema: option.unknown() });
