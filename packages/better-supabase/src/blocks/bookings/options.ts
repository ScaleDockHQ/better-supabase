import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.bookings.options`. */
export type BookingsSqlOptions = {
  /** Adds booking series: a recurrence rule that books every occurrence. */
  readonly recurring?: boolean;
};

export const bookingsSqlOptions: BlockOptionsSchema<BookingsSqlOptions> =
  blockOptions<BookingsSqlOptions>({
    recurring: option.boolean({ default: false }),
  });
