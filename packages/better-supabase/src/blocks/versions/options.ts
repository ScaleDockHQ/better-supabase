import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.versions.options`. */
export type VersionsSqlOptions = {
  readonly keep?: number;
  readonly debounce?: number;
  readonly extraColumns?: unknown;
};

export const versionsSqlOptions: BlockOptionsSchema<VersionsSqlOptions> =
  blockOptions<VersionsSqlOptions>({
    keep: option.number({ default: 50 }),
    debounce: option.number({ default: 300 }),
    extraColumns: option.unknown(),
  });
