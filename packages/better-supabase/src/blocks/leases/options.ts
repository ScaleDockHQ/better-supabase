import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leases.options`. */
export type LeasesSqlOptions = { readonly extraColumns?: unknown };

export const leasesSqlOptions: BlockOptionsSchema<LeasesSqlOptions> =
  blockOptions<LeasesSqlOptions>({ extraColumns: option.unknown() });
