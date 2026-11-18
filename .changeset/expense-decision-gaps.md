---
"better-supabase": minor
---

Expense and approval follow-ups to ADR 1090 (ADR 1091):

- The expenses guard stamps `createdBy` with the caller on a client's insert and refuses a client's change to it. The service role names a creator with `createExpense({ createdBy })` or `fields.created_by`; other trusted writers keep theirs, else the caller or the owner is recorded. An expense without a creator counts the decider as its creator, so it is decided or reopened only when nobody else can. Backfill `created_by` on older rows.
- `expenseSelfDecidesMany(ids)` (`expense_self_decides_many`) answers `expenseSelfDecides` for a whole list in one call.
- `options.decider` lets an app function decide standalone expenses, as in the leave block, and makes the "nobody else can decide" rule count the active managers up the owner's chain.
- `options.invoicedCheck` names an app function `(expense_id uuid) returns boolean`, so an expense on a cancelled invoice can be reopened.
- An approval policy snapshot takes `excludedUserIds`: those users leave the approvals queue, the notifications and the required-all holders, and their decision is refused. Standalone expenses exclude the creator while someone else can decide.
- Expense reports and lines get the guard triggers of standalone expenses: no client writes to the stamp columns or the owner, only the allowed transitions, the decider stamped, and owner, currency and lines frozen once approved (for a client, once submitted).
- State conflicts that raised `55000` now raise `PT409` (HTTP 409, a `conflict` error): `EXPENSE_LOCKED`, `EXPENSE_TRANSITION_INVALID`, `EXPENSE_REPORT_LOCKED`, `EXPENSE_IN_APPROVAL`, `LEAVE_REQUEST_CLOSED`, `IMPORT_RUN_NOT_RUNNING`, `TIME_TIMER_RUNNING`, `TIME_ENTRIES_TIMESHEET_APPROVED`, `TIME_ENTRIES_TIMESHEET_SUBMITTED`, `WEBHOOK_DELIVERY_IN_PROGRESS`, `LEDGER_ALREADY_REVERSED`, `ACCOUNTING_ENTRY_REVERSED`, `PERIOD_CLOSED` (fiscal year already closed), `INVOICE_ALREADY_APPROVED`, `INVOICE_NOT_DRAFT`, `INVOICE_PAYMENT_REVERSED`, `INVOICE_ALREADY_HANDED_OVER`, `ACTIVITY_ALREADY_MARKED_ERROR`, `AGENT_MANDATE_USED`, `ASSETS_DISPOSED`, `ATTACHMENT_NOT_CLAIMABLE`, `DECISION_SUPPORT_ALERT_STATUS`, `DSAR_CLOSED`, `DSAR_EXTENDED`, `DOCUMENT_SUGGESTION_CLOSED` and `SHIPMENT_PROOF_RECORDED`.
