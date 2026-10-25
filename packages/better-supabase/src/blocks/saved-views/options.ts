import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.saved-views.options`. */
export type SavedViewsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const savedViewsSqlOptions: BlockOptionsSchema<SavedViewsSqlOptions> =
  blockOptions<SavedViewsSqlOptions>({ extraColumns: option.extraColumns() });
