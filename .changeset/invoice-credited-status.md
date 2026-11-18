---
"better-supabase": minor
---

The invoices block takes `options.creditedStatus: true`, which moves an invoice whose credit notes cover its total and charges to a closed `credited` status instead of `paid`, unpaid or paid, without an `invoice.paid` event. Voiding an issued credit note now gives its credit back and moves the invoice to the status its balance gives. The status update after a payment or credit no longer clears the row it reports on when the invoice isn't in a settling status, so `invoice.credited` always carries the organization and invoice id.
