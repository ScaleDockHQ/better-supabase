import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.donations.options`. */
export type DonationsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const donationsSqlOptions: BlockOptionsSchema<DonationsSqlOptions> =
  blockOptions<DonationsSqlOptions>({ extraColumns: option.extraColumns() });
