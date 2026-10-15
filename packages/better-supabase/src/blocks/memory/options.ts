import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.memory.options`. */
export type MemorySqlOptions = {
  readonly dimensions?: unknown;
  readonly type?: unknown;
  readonly textSearch?: unknown;
  readonly maxContent?: number;
};

export const memorySqlOptions: BlockOptionsSchema<MemorySqlOptions> =
  blockOptions<MemorySqlOptions>({
    dimensions: option.unknown(),
    type: option.unknown(),
    textSearch: option.unknown(),
    maxContent: option.number({ default: 100_000 }),
  });
