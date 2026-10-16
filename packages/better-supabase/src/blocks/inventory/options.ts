import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.inventory.options`. */
export type InventorySqlOptions = {
  readonly extraColumns?: unknown;
};

export const inventorySqlOptions: BlockOptionsSchema<InventorySqlOptions> =
  blockOptions<InventorySqlOptions>({
    extraColumns: option.unknown(),
  });
