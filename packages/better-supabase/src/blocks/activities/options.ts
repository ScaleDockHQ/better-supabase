import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.activities.options`. */
export type ActivitiesSqlOptions = {
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

export const activitiesSqlOptions: BlockOptionsSchema<ActivitiesSqlOptions> =
  blockOptions<ActivitiesSqlOptions>({
    types: option.strings(),
    extraColumns: option.unknown(),
    recordings: option.boolean({ default: false }),
    bookings: option.boolean(),
  });
