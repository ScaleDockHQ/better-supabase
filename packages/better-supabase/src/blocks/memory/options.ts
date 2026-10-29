import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.memory.options`. */
export type MemorySqlOptions = {
  readonly dimensions?: unknown;
  readonly type?: unknown;
  readonly textSearch?: unknown;
  readonly maxContent?: number;
  /** `false` lets personal memory have no tenant. */
  readonly tenant?: boolean;
  /**
   * The most live archival facts per owner and tenant; older ones are
   * forgotten.
   */
  readonly maxItems?: number;
};

export const memorySqlOptions: BlockOptionsSchema<MemorySqlOptions> =
  blockOptions<MemorySqlOptions>({
    dimensions: option.unknown(),
    type: option.unknown(),
    textSearch: option.unknown(),
    maxContent: option.number({ default: 100_000 }),
    tenant: option.boolean({ default: true }),
    maxItems: option.number(),
  });
