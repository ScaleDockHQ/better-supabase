import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.expenses.options`. */
export type ExpensesSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  readonly categoryExtraColumns?: ExtraColumns;
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
  /**
   * Without reports: `withdrawExpense` also takes an approved expense that
   * isn't reimbursed back to draft and clears its decision. The owner may, and
   * so may a holder of `permissions.withdraw` (default the `update` key).
   */
  readonly withdrawApproved?: boolean;
};

export const expensesSqlOptions: BlockOptionsSchema<ExpensesSqlOptions> =
  blockOptions<ExpensesSqlOptions>({
    extraColumns: option.extraColumns(),
    categoryExtraColumns: option.extraColumns(),
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    companyExpenses: option.boolean({ default: false }),
    withdrawApproved: option.boolean({ default: false }),
  });
