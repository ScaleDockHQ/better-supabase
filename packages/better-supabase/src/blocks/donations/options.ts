import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.donations.options`. */
export type DonationsSqlOptions = { readonly extraColumns?: unknown };

export const donationsSqlOptions: BlockOptionsSchema<DonationsSqlOptions> =
  blockOptions<DonationsSqlOptions>({ extraColumns: option.unknown() });
