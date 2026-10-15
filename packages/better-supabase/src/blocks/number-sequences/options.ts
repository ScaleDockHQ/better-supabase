import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.number-sequences.options`. */
export type NumberSequencesSqlOptions = {
  readonly entities?: unknown;
};

export const numberSequencesSqlOptions: BlockOptionsSchema<NumberSequencesSqlOptions> =
  blockOptions<NumberSequencesSqlOptions>({
    entities: option.unknown(),
  });
