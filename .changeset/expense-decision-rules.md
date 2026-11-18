---
"better-supabase": minor
---

Expenses without reports keep their decision rules in the database (ADR 1090). Behaviour changes:

- A trigger on the expenses table stamps `decidedBy`, `decidedAt`, `reimbursedBy` and `reimbursedAt`, clears the decision when an expense goes back to submitted or draft, and refuses a client's own write to the status or those columns. A client's new row starts as a draft.
- The status moves only along the allowed transitions; an approved or reimbursed expense never goes straight to draft (`EXPENSE_TRANSITION_INVALID`).
- The owner and the creator (`createdBy`) can't approve or reject an expense unless nobody else can decide it, as the leave block's `selfDecideWhenTopOfChain` rule. The audit entry carries `selfDecided`.
- Only the owner resubmits a rejected expense.
- The amount, currency, category and owner are frozen once approved; the owner changes only in draft, and a client needs the create or update key for it.
- `reopenExpense({ expenseId, reason })` takes an approved expense back to submitted, and `reverseExpenseReimbursement({ expenseId, reason })` takes a reimbursed one back to approved; both keep the reason in the audit and record `expense.reopened` and `expense.reimbursement_reversed`. `options.invoicedColumn` makes `reopenExpense` refuse an invoiced expense.
- `options.withdrawApproved` is removed: `withdrawExpense` refuses a decided expense with `EXPENSE_ALREADY_DECIDED`. Reopen it instead.
- State conflicts (`EXPENSE_ALREADY_SUBMITTED`, `EXPENSE_ALREADY_DECIDED`, `EXPENSE_ALREADY_OPEN`, `EXPENSE_ALREADY_REIMBURSED`, `EXPENSE_NOT_REIMBURSED`, `EXPENSE_INVOICED`) raise SQLSTATE `PT409`, which PostgREST answers with 409 and `mapDbError` maps to a `conflict` error.
- `expenseSelfDecides(id)` (`expense_self_decides`) and the leave block's `selfDecides(organizationId)` (`leave_self_decides`) tell an app whether the caller decides their own record.
