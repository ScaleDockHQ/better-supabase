import type { BlockOf } from "../define-block.ts";
import type { ExpensesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { expensesEvents } from "./events.ts";
import { createExpenses } from "./expenses.ts";
import { expensesSqlOptions } from "./options.ts";
import {
  expenseCategoryInputSchema,
  expenseLineInputSchema,
  expenseReportInputSchema,
} from "./schemas.ts";

/** The `expenses` block's manifest (ADR 0029). */
export const expensesBlock: BlockOf<
  "expenses",
  typeof createExpenses,
  ExpensesEvents
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
  category: "commerce",
});
