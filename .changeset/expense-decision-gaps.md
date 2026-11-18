---
"better-supabase": minor
---

**Breaking:** 51 state refusals in 26 block modules move from SQLSTATE `55000` to `PT409`, so PostgREST answers HTTP 409 instead of 500 and `mapDbError` returns a `conflict` error. The hints are unchanged: `EXPENSE_LOCKED`, `EXPENSE_TRANSITION_INVALID`, `EXPENSE_REPORT_LOCKED`, `EXPENSE_IN_APPROVAL`, `LEAVE_REQUEST_CLOSED`, `IMPORT_RUN_NOT_RUNNING`, `TIME_TIMER_RUNNING`, `TIME_ENTRIES_TIMESHEET_APPROVED`, `TIME_ENTRIES_TIMESHEET_SUBMITTED`, `WEBHOOK_DELIVERY_IN_PROGRESS`, `LEDGER_ALREADY_REVERSED`, `ACCOUNTING_ENTRY_REVERSED`, `PERIOD_CLOSED` (fiscal year already closed), `INVOICE_ALREADY_APPROVED`, `INVOICE_NOT_DRAFT`, `INVOICE_PAYMENT_REVERSED`, `INVOICE_ALREADY_HANDED_OVER`, `ACTIVITY_ALREADY_MARKED_ERROR`, `AGENT_MANDATE_USED`, `ASSETS_DISPOSED`, `ATTACHMENT_NOT_CLAIMABLE`, `DECISION_SUPPORT_ALERT_STATUS`, `DSAR_CLOSED`, `DSAR_EXTENDED`, `DOCUMENT_SUGGESTION_CLOSED` and `SHIPMENT_PROOF_RECORDED`. Code that catches `55000` for them must catch `PT409`.

Expense and approval follow-ups to ADR 1090 (ADR 1091):

- The expenses guard stamps `createdBy` with the caller on a client's insert and refuses a client's change to it. The service role names a creator with `createExpense({ createdBy })` or `fields.created_by`; other trusted writers keep theirs, else the caller or the owner is recorded. The upgrade migration (expenses module version 2) backfills `created_by` with the owner's user on older rows; a row whose owner has no user keeps a null creator. An expense without a creator counts the decider as its creator, so it is decided or reopened only when nobody else can.
- `reopenExpense` lets the owner or creator reopen when nobody else can decide, like `decideExpense`.
- `expenseSelfDecidesMany(ids)` (`expense_self_decides_many`, `uuid[]`) answers `expenseSelfDecides` for a whole list in one call.
- `options.decider` lets an app function decide standalone expenses, as in the leave block, and makes the "nobody else can decide" rule count the active managers up the owner's chain.
- `options.invoicedCheck` names an app function `(expense_id uuid) returns boolean`, so an expense on a cancelled invoice can be reopened.
- An approval policy snapshot takes `excludedUserIds`: those users leave the approvals queue, the notifications and the required-all holders, and their decision is refused. Standalone expenses exclude the creator while someone else can decide.
- Expense reports and lines get the guard triggers of standalone expenses: no client writes to the stamp columns or the owner, only the allowed transitions, the decider stamped, and owner, currency and lines frozen once approved (for a client, once submitted). These guards also apply to the service role and `postgres`: a seed or import that adds lines to an approved report must insert the lines before approving it, or disable the trigger for its transaction as the expenses docs describe under Decision rules.
