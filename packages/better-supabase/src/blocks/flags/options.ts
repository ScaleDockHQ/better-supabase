import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.flags.options`. */
export type FlagsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const flagsSqlOptions: BlockOptionsSchema<FlagsSqlOptions> =
  blockOptions<FlagsSqlOptions>({
    extraColumns: option.unknown(),
  });
