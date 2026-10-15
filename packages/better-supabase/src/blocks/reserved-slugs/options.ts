import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.reserved-slugs.options`. */
export type ReservedSlugsSqlOptions = {
  readonly maxLength?: number;
  readonly minLength?: number;
  readonly slugs?: readonly string[];
};

export const reservedSlugsSqlOptions: BlockOptionsSchema<ReservedSlugsSqlOptions> =
  blockOptions<ReservedSlugsSqlOptions>({
    maxLength: option.number({ default: 63 }),
    minLength: option.number({ default: 1 }),
    slugs: option.strings({ default: [] }),
  });
