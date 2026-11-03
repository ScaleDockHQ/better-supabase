import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.commissions.options`. */
export type CommissionsSqlOptions = {
  /**
   * Accrue a commission for the seller (`created_by`) when a sales invoice
   * becomes paid. Needs the invoices block with a `createdBy` column. Default
   * `false`.
   */
  readonly invoices?: boolean;
};

export const commissionsSqlOptions: BlockOptionsSchema<CommissionsSqlOptions> =
  blockOptions<CommissionsSqlOptions>({ invoices: option.boolean() });
