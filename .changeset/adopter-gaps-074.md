---
"better-supabase": patch
---

Expense, invoice and leave follow-ups:

- An expense without a creator, such as a company expense the service role recorded, no longer counts every decider as its creator (ADR 1093). Before, two or more approvers each saw the other as someone else who could decide, so nobody could decide it. An expense with a creator keeps the rule that its owner or creator decides only when nobody else can.
- `recomputeStatus(invoiceId)` (`recompute_invoice_status(invoice uuid)`) derives an issued invoice's status, paid total and credited total from its payments and issued credit notes, including `credited` with `options.creditedStatus`, so an app never writes the status itself. It also restores invoices whose credit notes were voided before 0.73. Needs `invoices.manage`.
- `requestSelfDecides(requestId)` (`leave_request_self_decides(request_id uuid)`) tells whether the caller decides a leave request as its requester under `options.selfDecideWhenTopOfChain`, and `decide_leave_request` uses the same function.
