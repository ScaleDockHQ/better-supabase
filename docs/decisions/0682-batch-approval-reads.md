# 0682: Read invoice approvals and approval requests in batches

- Status: accepted
- Date: 2026-11-11
- Amends: 0670

## Context

CentraKit's doctor run (BS634) found two loops that read one approval per call: a bill list that
called `invoices.approvalStatus(id)` for every bill on the page, and the approvals sweep job that
called `approvals.get(id)` for every request it escalated or expired before notifying about it.
Neither block had a batch method, so an app could not do better without its own SQL.

## Decision

Each block gets one function that takes a uuid array, following ADR 0670.

| Block       | SQL function                                             | Client method                  |
| ----------- | -------------------------------------------------------- | ------------------------------ |
| `invoices`  | `purchase_invoice_approval_statuses(invoice_ids uuid[])` | `approvalStatuses(invoiceIds)` |
| `approvals` | `get_approvals(request_ids uuid[])`                      | `getMany(ids)`                 |

`purchase_invoice_approval_statuses` returns an object keyed by invoice id, since a bill list looks
the status up per row; the client turns it into a `Map`. `get_approvals` returns an array in the
order of the ids, with the same shape as `get_approval`. Both leave out an id the caller cannot read
instead of failing the batch, and both run the read check of the single function per row.

## Consequences

`security-definer-functions` in `tests/sql/practices-baseline.json` rises by six for `approvals` and
`invoices` (one function times six rendered variants each). Both single reads are definer functions
because their checks read tables the caller may not (the approval eligibility and subject checks,
the invoice permission), so the batch reads are too. This is a deliberate exception to the rule that
definer counts go down.
