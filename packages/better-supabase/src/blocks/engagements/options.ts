import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.engagements.options`. */
export type EngagementsSqlOptions = {
  readonly types?: readonly string[];
  readonly extraColumns?: unknown;
};

export const engagementsSqlOptions: BlockOptionsSchema<EngagementsSqlOptions> =
  blockOptions<EngagementsSqlOptions>({
    types: option.strings(),
    extraColumns: option.unknown(),
  });
