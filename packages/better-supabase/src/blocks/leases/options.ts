import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leases.options`. */
export type LeasesSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * Adds a gist exclusion constraint (ADR 0198) so a unit has at most one
   * active lease per day. Needs `btree_gist`, which the module creates. Rows
   * that already overlap make the migration fail. Default `false`.
   */
  readonly noOverlap?: boolean;
};

export const leasesSqlOptions: BlockOptionsSchema<LeasesSqlOptions> =
  blockOptions<LeasesSqlOptions>({
    extraColumns: option.extraColumns(),
    noOverlap: option.boolean({ default: false }),
  });
