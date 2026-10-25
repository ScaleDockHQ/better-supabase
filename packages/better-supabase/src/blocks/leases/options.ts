import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leases.options`. */
export type LeasesSqlOptions = { readonly extraColumns?: ExtraColumns };

export const leasesSqlOptions: BlockOptionsSchema<LeasesSqlOptions> =
  blockOptions<LeasesSqlOptions>({ extraColumns: option.extraColumns() });
