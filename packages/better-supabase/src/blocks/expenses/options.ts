import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.expenses.options`. */
export type ExpensesSqlOptions = {
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
   * Without reports: a column of the expenses table that is set once the
   * expense is billed onward, such as `invoice_id`. `reopenExpense` refuses an
   * expense where it isn't null (`EXPENSE_INVOICED`, a 409 conflict).
   */
  readonly invoicedColumn?: string;
  /**
   * Without reports: each submitted expense files a request with the approvals
   * block, whose final decision approves or rejects it. `decideExpense` is
   * refused while that request waits. The expense's owner is the requester;
   * with `owner: "employee"`, a manager step asks the employee's manager.
   */
  readonly standaloneApprovals?: boolean;
  /**
   * The approval policy of `standaloneApprovals`. Default: one step for holders
   * of the approve permission.
   */
  readonly policy?: unknown;
  /**
   * `"manager"`: the owner's manager (the employees block) decides through
   * `decideExpense` and `decideExpenseReport` too, next to holders of the
   * approve permission. Default `"permission"`.
   */
  readonly approver?: "permission" | "manager";
};

export const expensesSqlOptions: BlockOptionsSchema<ExpensesSqlOptions> =
  blockOptions<ExpensesSqlOptions>({
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    companyExpenses: option.boolean({ default: false }),
    invoicedColumn: option.string({ default: "" }),
    standaloneApprovals: option.boolean({ default: false }),
    policy: option.unknown(),
    approver: option.string<"permission" | "manager">({
      default: "permission",
    }),
  });
