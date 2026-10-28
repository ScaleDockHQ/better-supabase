import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.expenses.options`. */
export type ExpensesSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * `false` runs expenses without the approvals block: a submitted report waits
   * until `decide_expense_report` approves or rejects it.
   */
  readonly approvals?: boolean;
  readonly owner?: "user" | "employee";
  /**
   * Without reports: `createExpense` with `company: true` records an expense of
   * the organization itself, without a member or employee. Its owner column
   * must allow null.
   */
  readonly companyExpenses?: boolean;
};

export const expensesSqlOptions: BlockOptionsSchema<ExpensesSqlOptions> =
  blockOptions<ExpensesSqlOptions>({
    extraColumns: option.extraColumns(),
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    companyExpenses: option.boolean({ default: false }),
  });
