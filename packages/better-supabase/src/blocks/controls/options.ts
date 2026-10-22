import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.controls.options`. */
export type ControlsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const controlsSqlOptions: BlockOptionsSchema<ControlsSqlOptions> =
  blockOptions<ControlsSqlOptions>({
    extraColumns: option.unknown(),
  });
