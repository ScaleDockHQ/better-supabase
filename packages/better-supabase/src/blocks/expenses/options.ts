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
   * Without reports: an app function `"schema.function"`, `(expense_id uuid)
   * returns boolean`, that says whether the expense counts as invoiced, for
   * example only while its invoice isn't cancelled. `reopenExpense` refuses the
   * expense when it answers true or null. Use it instead of `invoicedColumn`,
   * not with it.
   */
  readonly invoicedCheck?: string;
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
  /**
   * Without reports: an app function `"schema.function"`, `(id uuid) returns
   * boolean`, that lets more callers decide an expense through `decideExpense`,
   * such as the managers up the owner's reporting chain. A null answer denies.
   * With it, the owner or creator decides only when no active manager up the
   * chain can either, as in the leave block.
   */
  readonly decider?: string;
  /**
   * With `standaloneApprovals`, the owner decides their own expense's approval
   * request when nobody else can: they hold the approve permission (or the
   * decider accepts them), no other active member holds it, and no active
   * manager with a login can decide it (`approver: "manager"`, or anyone up the
   * chain with a `decider`), as in the leave block. The policy's approvers must
   * be the approve permission, the manager or the decider. Default `false`.
   */
  readonly selfDecideWhenTopOfChain?: boolean;
};

export const expensesSqlOptions: BlockOptionsSchema<ExpensesSqlOptions> =
  blockOptions<ExpensesSqlOptions>({
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    companyExpenses: option.boolean({ default: false }),
    invoicedColumn: option.string({ default: "" }),
    invoicedCheck: option.string(),
    standaloneApprovals: option.boolean({ default: false }),
    policy: option.unknown(),
    approver: option.string<"permission" | "manager">({
      default: "permission",
    }),
    decider: option.string(),
    selfDecideWhenTopOfChain: option.boolean({ default: false }),
  });
