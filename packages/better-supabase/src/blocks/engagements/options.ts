import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.engagements.options`. */
export type EngagementsSqlOptions = {
  readonly types?: readonly string[];
};

export const engagementsSqlOptions: BlockOptionsSchema<EngagementsSqlOptions> =
  blockOptions<EngagementsSqlOptions>({
    types: option.strings(),
  });
