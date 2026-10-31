import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.banking.options`. */
export type BankingSqlOptions = {
  /** Extra columns on the bank accounts table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const bankingSqlOptions: BlockOptionsSchema<BankingSqlOptions> =
  blockOptions<BankingSqlOptions>({ extraColumns: option.extraColumns() });
