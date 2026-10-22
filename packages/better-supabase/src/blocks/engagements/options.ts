import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.engagements.options`. */
export type EngagementsSqlOptions = {
  readonly types?: readonly string[];
  readonly extraColumns?: unknown;
  /**
   * Recordings of calls and meetings as ai-files files, their transcripts and
   * notes on each engagement. Needs the ai-files block. Default `false`.
   */
  readonly recordings?: boolean;
  /**
   * Log a `meeting` engagement for each confirmed booking, on the person with
   * the booker's email and their company. Needs the bookings block. Default:
   * false.
   */
  readonly bookings?: boolean;
};

export const engagementsSqlOptions: BlockOptionsSchema<EngagementsSqlOptions> =
  blockOptions<EngagementsSqlOptions>({
    types: option.strings(),
    extraColumns: option.unknown(),
    recordings: option.boolean({ default: false }),
    bookings: option.boolean(),
  });
