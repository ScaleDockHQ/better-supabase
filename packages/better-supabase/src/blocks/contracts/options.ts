import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.contracts.options`. */
export type ContractsSqlOptions = {
  /** Days before the notice deadline the owner's renewal reminder fires. */
  readonly reminderDays?: number;
  readonly extraColumns?: ExtraColumns;
};

export const contractsSqlOptions: BlockOptionsSchema<ContractsSqlOptions> =
  blockOptions<ContractsSqlOptions>({
    reminderDays: option.number({ default: 14 }),
    extraColumns: option.extraColumns(),
  });
