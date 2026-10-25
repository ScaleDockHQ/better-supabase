import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.collections.options`. */
export type CollectionsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const collectionsSqlOptions: BlockOptionsSchema<CollectionsSqlOptions> =
  blockOptions<CollectionsSqlOptions>({ extraColumns: option.extraColumns() });
