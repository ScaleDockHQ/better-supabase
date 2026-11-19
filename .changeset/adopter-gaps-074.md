---
"better-supabase": minor
---

Expense, invoice and leave follow-ups:

- An expense without a creator, such as a company expense the service role recorded, no longer counts every decider as its creator (ADR 1093). Before, two or more approvers each saw the other as someone else who could decide, so nobody could decide it. A service caller acting for a user must now pass `createdBy`; without it the user who recorded the expense may decide it unless they are its owner. An expense with a creator keeps the rule that its owner or creator decides only when nobody else can.
- `recomputeStatus(invoiceId)` (`recompute_invoice_status(invoice uuid)`) derives an issued invoice's status, paid total and credited total from its ledger payments, imported allocations and issued credit notes, including `credited` with `options.creditedStatus`, so an app never writes the status itself. The paid total never drops below the stored one, so an import's row settlement keeps its total. A draft, void or uncollectible invoice keeps its status but gets its totals rewritten, and `invoice.paid` is recorded only for an invoice that was never paid. It also restores invoices whose credit notes were voided before 0.73. Needs `invoices.manage`, or `invoices.purchase` for a purchase invoice.
- `requestSelfDecides(requestId)` (`leave_request_self_decides(request_id uuid)`) tells whether the caller decides a leave request as its requester under `options.selfDecideWhenTopOfChain`, and `decide_leave_request` uses the same function.
