import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.expenses.options`. */
export type ExpensesSqlOptions = { readonly extraColumns?: unknown };

export const expensesSqlOptions: BlockOptionsSchema<ExpensesSqlOptions> =
  blockOptions<ExpensesSqlOptions>({ extraColumns: option.unknown() });
