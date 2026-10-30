import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.activities.options`. */
export type ActivitiesSqlOptions = {
  readonly types?: readonly string[];
  readonly extraColumns?: ExtraColumns;
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
  /**
   * The categories a progress note can take. Default: `general`, `care`,
   * `medical`, `behavior`, `family` and `incident`.
   */
  readonly noteCategories?: readonly string[];
  /**
   * Hours after logging that an engagement of a `lockTypes` type locks; `0`
   * locks it at once. Default 24.
   */
  readonly lockAfterHours?: number;
  /** The engagement types that lock. Default: `note` and `report`. */
  readonly lockTypes?: readonly string[];
};

export const activitiesSqlOptions: BlockOptionsSchema<ActivitiesSqlOptions> =
  blockOptions<ActivitiesSqlOptions>({
    types: option.strings(),
    extraColumns: option.extraColumns(),
    recordings: option.boolean({ default: false }),
    bookings: option.boolean(),
    noteCategories: option.strings({
      default: ["general", "care", "medical", "behavior", "family", "incident"],
    }),
    lockAfterHours: option.number({ default: 24 }),
    lockTypes: option.strings({ default: ["note", "report"] }),
  });
