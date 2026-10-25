import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.inventory.options`. */
export type InventorySqlOptions = { readonly extraColumns?: ExtraColumns };

export const inventorySqlOptions: BlockOptionsSchema<InventorySqlOptions> =
  blockOptions<InventorySqlOptions>({ extraColumns: option.extraColumns() });
