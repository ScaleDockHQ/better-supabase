import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.versions.options`. */
export type VersionsSqlOptions = {
  readonly subjects?: unknown;
  readonly keep?: number;
  readonly debounce?: number;
};

export const versionsSqlOptions: BlockOptionsSchema<VersionsSqlOptions> =
  blockOptions<VersionsSqlOptions>({
    subjects: option.unknown(),
    keep: option.number({ default: 50 }),
    debounce: option.number({ default: 300 }),
  });
