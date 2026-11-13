import type { RecordBinding } from "../record-bindings.ts";
import type { ExpenseReport, Expenses } from "./expenses.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The expense reports of a member, newest first: the subject's `id` is the
 * member's user id. It reads through `expenses.list` with `userId`, which takes
 * the organization from the block's `tenant` option and needs `expenses.read`
 * for another member. Reports are keyed by member, not by employee. Filing or
 * deciding a report takes money, lines and receipts, so the binding has no
 * writes.
 */
export const expensesBinding: RecordBinding<
  Expenses,
  readonly ExpenseReport[]
> = defineRecordBinding({
  permissions: { read: "read" },
  module: "expenses",
  load: (client: Expenses, subject) => client.list({ userId: subject.id }),
  events: ["expense_report.*"],
});
