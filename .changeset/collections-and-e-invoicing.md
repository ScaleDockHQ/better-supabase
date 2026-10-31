---
"better-supabase": minor
---

The `invoices` block now collects. `recordPartyPayment(organizationId, payment)` splits one
payment from a customer over several of its invoices and keeps the rest as party credit on the
ledger, `applyPartyCredit(partyId, invoiceId, amount)` pays an invoice from it, and
`partyCredits(organizationId, partyId)` reads the credit per currency. Dunning levels
(`setDunningLevels`, `dunningLevels`) set the reminder, fee and final notice for each number of
days past due; `runDunning()` runs as the service role on the manifest's daily `dunning` schedule,
adds the level's fee as a charge, notifies the invoice's creator and records
`invoice.dunning_escalated`. `pauseDunning(invoiceId, until, reason?)` holds the reminders during a
dispute and needs the new `invoices.collect` permission. Invoices return `dunning: { level, at,
pausedUntil }`. The docs add a recurring invoice recipe on template schedules.

The new `better-supabase/e-invoicing` subpath writes an issued invoice or credit note as UBL 2.1 per
EN 16931 and Peppol BIS Billing 3.0 (`toUbl`), reads a received one into purchase bill input
(`fromUbl`, which loads the new optional peer `fast-xml-parser`), and defines the
`EInvoiceChannel` port (`apiVersion: 1`, checked with `eInvoiceChannelOf`) for an access point.
None is bundled. Apply the new migration with `better-supabase upgrade`.
