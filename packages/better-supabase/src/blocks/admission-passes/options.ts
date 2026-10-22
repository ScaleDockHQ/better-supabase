import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['admission-passes'].options`. */
export type AdmissionPassesSqlOptions = {
  /** How long before a booking starts its ticket admits, as a Postgres interval. */
  readonly checkInOpens?: string;
  /** How long a drop-in counts against a resource's capacity. */
  readonly dropInLength?: string;
  /**
   * Lets a pass with a number of uses pay for bookings. Needs bookings. Off by
   * default.
   */
  readonly credits?: boolean;
  /** How long before a class a cancellation still refunds its credit. */
  readonly creditRefundBefore?: string;
};

export const admissionPassesSqlOptions: BlockOptionsSchema<AdmissionPassesSqlOptions> =
  blockOptions<AdmissionPassesSqlOptions>({
    checkInOpens: option.string({ default: "1 hour" }),
    dropInLength: option.string({ default: "2 hours" }),
    credits: option.boolean({ default: false }),
    creditRefundBefore: option.string({ default: "12 hours" }),
  });
