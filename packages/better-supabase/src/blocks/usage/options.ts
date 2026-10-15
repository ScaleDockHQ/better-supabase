import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.usage.options`. */
export type UsageSqlOptions = {
  readonly meters?: unknown;
  readonly history?: boolean;
};

export const usageSqlOptions: BlockOptionsSchema<UsageSqlOptions> =
  blockOptions<UsageSqlOptions>({
    meters: option.unknown(),
    history: option.boolean({ default: false }),
  });
