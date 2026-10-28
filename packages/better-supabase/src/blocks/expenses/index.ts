export {
  createExpenses,
  type Expense,
  type ExpenseInput,
  type ExpenseListOptions,
  type ExpenseStatus,
  type ExpenseUpdate,
  type ExpenseCategory,
  type ExpenseCategoryInput,
  type ExpenseLine,
  type ExpenseLineInput,
  type ExpenseLineUpdate,
  type ExpensePolicyViolation,
  type ExpenseReport,
  type ExpenseReportInput,
  type ExpenseReportListOptions,
  type ExpenseReportStatus,
  type Expenses,
  type ExpensesOptions,
  type ReimbursementInput,
} from "./expenses.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { expensesBlock } from "./manifest.ts";

export {
  expenseCategoryInputSchema,
  expenseLineInputSchema,
  expenseReportInputSchema,
} from "./schemas.ts";

export { expensesEvents } from "./events.ts";

export type {
  ExpenseEventData,
  ExpenseReportEventData,
  ExpenseReportPostedEventData,
  ExpenseReportSubmittedEventData,
  ExpensesEvents,
} from "./events.ts";
