---
"better-supabase": minor
---

`sendEInvoice` now keeps the `externalRef` the channel returns. The invoices module has a new optional table `invoice_deliveries` and the functions `record_invoice_delivery` and `list_invoice_deliveries`, and the invoices client gains `recordEInvoice` and `eInvoiceDeliveries`.

`sendEInvoice` takes the invoices client as `invoices` and returns a `deliveryId`. Passing it is required: replace your own save of the reference with `sendEInvoice({ invoice, format, channel, invoices })`. When the channel accepted the document but keeping the reference failed, the error names the `externalRef`; record it with `recordEInvoice` instead of sending again. Run `better-supabase upgrade` and generate a migration.
