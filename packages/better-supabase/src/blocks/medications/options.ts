import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.medications.options`. */
export type MedicationsSqlOptions = {
  /**
   * Minutes after its planned time a dose that nobody recorded counts as
   * missed, for `markMissed`. 1 to 1440. Default 60.
   */
  readonly missedAfterMinutes?: number;
  /**
   * The case kind a missed dose opens, linked to the order's record, when the
   * cases block is installed, such as `incident`. Default: no case.
   */
  readonly missedCaseKind?: string;
  /**
   * The IANA time zone schedule times, start dates and the chart's default day
   * are in. Default `UTC`.
   */
  readonly timeZone?: string;
  /** Extra columns on the medication orders table. */
  /**
   * A guest with a read grant on a record reads its medication orders, doses
   * and the medications they name (needs the `guests` block or an authorization
   * provider with `portalSubjects`). Default false.
   */
  readonly guestRead?: boolean;
  /** Extra columns on the medications table. */
  /** Extra columns on the medication administrations table. */
};

export const medicationsSqlOptions: BlockOptionsSchema<MedicationsSqlOptions> =
  blockOptions<MedicationsSqlOptions>({
    missedAfterMinutes: option.number({ default: 60 }),
    missedCaseKind: option.string(),
    timeZone: option.string({ default: "UTC" }),
    guestRead: option.boolean(),
  });
