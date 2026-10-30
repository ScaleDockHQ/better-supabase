import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.manufacturing.options`. */
export type ManufacturingSqlOptions = {
  /** Extra columns on the production orders table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const manufacturingSqlOptions: BlockOptionsSchema<ManufacturingSqlOptions> =
  blockOptions<ManufacturingSqlOptions>({
    extraColumns: option.extraColumns(),
  });
