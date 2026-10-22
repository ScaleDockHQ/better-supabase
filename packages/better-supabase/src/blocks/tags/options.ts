import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tags.options`. */
export type TagsSqlOptions = { readonly extraColumns?: unknown };

export const tagsSqlOptions: BlockOptionsSchema<TagsSqlOptions> =
  blockOptions<TagsSqlOptions>({ extraColumns: option.unknown() });
