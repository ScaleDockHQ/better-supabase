import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tags.options`. */
export type TagsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const tagsSqlOptions: BlockOptionsSchema<TagsSqlOptions> =
  blockOptions<TagsSqlOptions>({ extraColumns: option.extraColumns() });
