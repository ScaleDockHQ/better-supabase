import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.medications.options`. */
export type MedicationsSqlOptions = {
  /**
   * Minutes after its planned time a dose that nobody recorded counts as
   * missed, for `markMissed`. 1 to 1440. Default 60.
   */
  readonly missedAfterMinutes?: number;
  /**
   * The IANA time zone schedule times, start dates and the chart's default day
   * are in. Default `UTC`.
   */
  readonly timeZone?: string;
  /** Extra columns on the medication orders table. */
  readonly extraColumns?: ExtraColumns;
};

export const medicationsSqlOptions: BlockOptionsSchema<MedicationsSqlOptions> =
  blockOptions<MedicationsSqlOptions>({
    missedAfterMinutes: option.number({ default: 60 }),
    timeZone: option.string({ default: "UTC" }),
    extraColumns: option.extraColumns(),
  });
