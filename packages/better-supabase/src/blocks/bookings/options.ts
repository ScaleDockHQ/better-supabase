import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.bookings.options`. */
export type BookingsSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /** Adds booking series: a recurrence rule that books every occurrence. */
  readonly recurring?: boolean;
};

export const bookingsSqlOptions: BlockOptionsSchema<BookingsSqlOptions> =
  blockOptions<BookingsSqlOptions>({
    extraColumns: option.extraColumns(),
    recurring: option.boolean({ default: false }),
  });
