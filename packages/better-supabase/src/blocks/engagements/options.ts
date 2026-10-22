import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.engagements.options`. */
export type EngagementsSqlOptions = {
  readonly types?: readonly string[];
  readonly extraColumns?: unknown;
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
    bookings: option.boolean(),
  });
