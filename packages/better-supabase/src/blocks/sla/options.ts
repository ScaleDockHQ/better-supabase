import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.sla.options`. */
export type SlaSqlOptions = { readonly businessHours?: unknown };

export const slaSqlOptions: BlockOptionsSchema<SlaSqlOptions> =
  blockOptions<SlaSqlOptions>({ businessHours: option.unknown() });
