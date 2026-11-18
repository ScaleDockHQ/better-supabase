---
"better-supabase": minor
---

The invoices block takes `options.creditedStatus: true`, which moves an invoice whose credit notes cover its total and charges to a closed `credited` status instead of `paid`, unpaid or paid, without an `invoice.paid` event. Behaviour changes for every adopter:

- `invoice.paid` is recorded only when an invoice moves to `paid`; a credit note on an invoice that was already paid no longer records it again.
- Voiding an issued credit note gives its credit back and moves the original invoice to the status its balance gives (for example `paid` back to `issued`), with or without `creditedStatus`, and a state machine over the invoices table records that `status.changed`. Credit notes voided before this release are not restored retroactively.
- The status update after a payment or credit no longer clears the row it reports on when the invoice isn't in a settling status, so `invoice.credited` always carries the organization and invoice id.
