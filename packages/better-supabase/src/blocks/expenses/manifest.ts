import type { BlockOf } from "../define-block.ts";
import type { ExpensesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { expensesEvents } from "./events.ts";
import { createExpenses } from "./expenses.ts";
import { expensesSqlOptions } from "./options.ts";
import { expensesBinding } from "./record-binding.ts";
import {
  expenseCategoryInputSchema,
  expenseLineInputSchema,
  expenseReportInputSchema,
} from "./schemas.ts";

/** The `expenses` block's manifest (ADR 0029). */
export const expensesBlock: BlockOf<
  "expenses",
  typeof createExpenses,
  ExpensesEvents,
  Record<never, never>,
  never,
  typeof expensesBinding
> = defineBlock({
  name: "expenses",
  sql: ["expenses"],
  options: { expenses: expensesSqlOptions },
  events: expensesEvents,
  schemas: {
    expense_report: { input: expenseReportInputSchema },
    expense_line: { input: expenseLineInputSchema },
    expense_category: { input: expenseCategoryInputSchema },
  },
  create: createExpenses,
  record: expensesBinding,
  category: "commerce",
  entities: {
    expense_report: { mutability: "state-machine", emits: { create: true } },
    expense_line: {
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
    expense_category: { mutability: "editable", emits: { update: false } },
  },
  description:
    "Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units. Without reports, each expense is one row a member or an employee submits and the app decides.",
});
