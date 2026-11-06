import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.inventory.options`. */
export type InventorySqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * An inspection kind of the inspections block (`blocks.inspections.options
   * .kinds`): each goods receipt opens an inspection of that kind.
   */
  readonly receiptInspection?: string;
  /** Purchase orders can be template rows. ADR 0244. */
  readonly templates?: boolean;
};

export const inventorySqlOptions: BlockOptionsSchema<InventorySqlOptions> =
  blockOptions<InventorySqlOptions>({
    extraColumns: option.extraColumns(),
    receiptInspection: option.string(),
    templates: option.boolean({ default: false }),
  });
