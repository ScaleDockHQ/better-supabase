import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.hiring.options`. */
export type HiringSqlOptions = {
  readonly candidate?: string;
  readonly extraColumns?: ExtraColumns;
};

export const hiringSqlOptions: BlockOptionsSchema<HiringSqlOptions> =
  blockOptions<HiringSqlOptions>({
    candidate: option.string({ default: "person" }),
    extraColumns: option.extraColumns(),
  });
