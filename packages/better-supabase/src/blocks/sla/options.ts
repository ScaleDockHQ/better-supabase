import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.sla.options`. */
export type SlaSqlOptions = {
  readonly businessHours?: unknown;
  readonly subjects?: unknown;
  readonly extraColumns?: unknown;
};

export const slaSqlOptions: BlockOptionsSchema<SlaSqlOptions> =
  blockOptions<SlaSqlOptions>({
    businessHours: option.unknown(),
    subjects: option.unknown(),
    extraColumns: option.unknown(),
  });
