import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.usage.options`. */
export type UsageSqlOptions = {
  readonly meters?: unknown;
  readonly history?: boolean;
  readonly partitioned?: boolean;
};

export const usageSqlOptions: BlockOptionsSchema<UsageSqlOptions> =
  blockOptions<UsageSqlOptions>({
    meters: option.unknown(),
    history: option.boolean({ default: false }),
    partitioned: option.boolean({ default: false }),
  });
