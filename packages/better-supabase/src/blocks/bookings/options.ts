import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.bookings.options`. */
export type BookingsSqlOptions = {
  readonly extraColumns?: unknown;
  /** Adds booking series: a recurrence rule that books every occurrence. */
  readonly recurring?: boolean;
};

export const bookingsSqlOptions: BlockOptionsSchema<BookingsSqlOptions> =
  blockOptions<BookingsSqlOptions>({
    extraColumns: option.unknown(),
    recurring: option.boolean({ default: false }),
  });
