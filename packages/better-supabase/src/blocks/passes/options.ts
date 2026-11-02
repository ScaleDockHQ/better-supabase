import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['passes'].options`. */
export type PassesSqlOptions = {
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
  /**
   * Adds a gist exclusion constraint (ADR 0198) so a holder has at most one
   * active pass of a kind per resource at a time. Needs `btree_gist`, which the
   * module creates. Rows that already overlap make the migration fail. Default
   * `false`.
   */
  readonly noOverlap?: boolean;
};

export const passesSqlOptions: BlockOptionsSchema<PassesSqlOptions> =
  blockOptions<PassesSqlOptions>({
    checkInOpens: option.string({ default: "1 hour" }),
    dropInLength: option.string({ default: "2 hours" }),
    credits: option.boolean({ default: false }),
    creditRefundBefore: option.string({ default: "12 hours" }),
    noOverlap: option.boolean({ default: false }),
  });
