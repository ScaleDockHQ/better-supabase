import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.sla.options`. */
export type SlaSqlOptions = {
  readonly businessHours?: unknown;
  readonly extraColumns?: ExtraColumns;
};

export const slaSqlOptions: BlockOptionsSchema<SlaSqlOptions> =
  blockOptions<SlaSqlOptions>({
    businessHours: option.unknown(),
    extraColumns: option.extraColumns(),
  });
