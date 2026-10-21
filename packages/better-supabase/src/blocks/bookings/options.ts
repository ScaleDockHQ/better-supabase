import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.bookings.options`. */
export type BookingsSqlOptions = { readonly extraColumns?: unknown };

export const bookingsSqlOptions: BlockOptionsSchema<BookingsSqlOptions> =
  blockOptions<BookingsSqlOptions>({ extraColumns: option.unknown() });
