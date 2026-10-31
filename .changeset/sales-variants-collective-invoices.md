---
"better-supabase": minor
---

Quotes and orders can have variants, and invoices can be built from several sources at once.
`quotes.createVariant`, `listVariants` and `selectVariant` (with `forward: "order" | "invoice"`) manage
alternative versions of one quote, and an unselected variant can't become an order or invoice.
`orders.setVariant`, `listVariants` and `selectVariant` do the same for orders. New columns on `quotes` and
`orders`: `variant_of`, `variant_label` and `is_selected`; existing databases get them from the migration
`sales_variants_collective_invoices`. `invoices.invoiceFromSources` bills delivered orders, shipments and
unbilled time for one party, one invoice per billing party and currency, keeps each line's origin in the
new `invoice_line_sources` table, invoices every source once, and supports partial quantities of order
lines. `invoices.sourcesReadyToInvoice` lists what is left to bill.
