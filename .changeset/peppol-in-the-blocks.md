---
"better-supabase": minor
---

Peppol support in the invoices block, with one channel port.

- `better-supabase/e-invoicing` now owns `EInvoiceFormat`, `EInvoiceChannel` and `EInvoiceDocument`, and adds `peppolBis3Format`. The channel's optional `lookup`, `status` and `receive` methods check a participant, ask the network and poll for documents. `testEInvoiceChannel` in `better-supabase/testing` is its conformance kit.
- The invoices block adds `invoice_e_endpoints` (participant ids of an organization, legal entity or company) and `invoice_e_deliveries` (the delivery log), the `invoices.send` permission, four `invoice.e_invoice_*` events, and the methods `sendEInvoice`, `recordEInvoiceDelivery`, `syncEInvoices`, `receiveEInvoices`, `setEInvoiceEndpoint`, `eInvoiceEndpoints` and `eInvoiceDeliveries`.
- Breaking: the `better-supabase/blocks/invoices` exports `sendEInvoice` (as a function), `EInvoiceChannel`, `EInvoiceFormat`, `EInvoiceContext`, `EInvoiceDocument`, `EInvoiceStatus`, `eInvoiceChannelOf` and `eInvoiceFormatOf` are gone. Import the types and the `of` functions from `better-supabase/e-invoicing` and call `invoices.sendEInvoice` instead.

| Before                                                | After                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------ |
| `sendEInvoice({ invoice, format, channel })`          | `invoices.sendEInvoice(invoice, { format, channel })`              |
| channel `name`                                        | channel `key`                                                      |
| `send(document, context)` returning `{ externalRef }` | `send(document, { recipient, invoice })` returning `{ messageId }` |
| `status(externalRef, context)`                        | `status(messageId, context)`                                       |
| document `{ body, filename, contentType }`            | document `{ type, id, xml }`                                       |

Run the new migration (or `better-supabase db diff`) to add the two tables and grant `invoices.send` to the roles that send invoices.
