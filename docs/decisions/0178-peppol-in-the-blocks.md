# 0178: Invoices keep Peppol participant ids and a delivery log behind one channel port

- Status: accepted
- Date: 2026-11-01
- Amends: 0151, 0159
- Supersedes: 0175

## Context

`better-supabase/e-invoicing` wrote and read UBL, and the invoices block had its
own `EInvoiceChannel` whose `send` returned an `externalRef` that nothing stored.
The two packages each declared a channel, a format and a document type, so a
channel written for one did not fit the other. Peppol also needs a participant id
(an EAS scheme and an id) on both parties, and a record of what was sent,
delivered, rejected or received. The library is not released yet, so the ports can
break.

## Decision

- One port. `EInvoiceFormat`, `EInvoiceChannel` and `EInvoiceDocument` live in
  `better-supabase/e-invoicing` (`apiVersion: 1`). The document is UBL
  (`{ type, id, xml }`), the channel is identified by `key` and `send` returns a
  `messageId`. `lookup`, `status` and `receive` are optional. The blocks entry
  re-exports nothing of them. `peppolBis3Format` is the one format better-supabase
  ships, and `testEInvoiceChannel` is the conformance kit.
- Participant ids are rows of `invoice_e_endpoints` (party kind `organization`,
  `legal_entity` or `company`, a scheme and an id), not columns on `legal_entities`
  and `companies`. Those blocks stay untouched and adoptable, and a table the app
  owns needs no new columns. A seller reads its legal entity, then the
  organization. The buyer reads the invoice's company.
- Deliveries are rows of `invoice_e_deliveries`, unique per tenant, channel and
  message id, with `direction`, `state` (`pending`, `delivered`, `rejected`,
  `received`, `unmatched`) and a SHA-256 of the document. Sending, a state change
  and a received bill record `invoice.e_invoice_sent`, `_delivered`, `_rejected`
  and `_received` through the usual event path.
- The block methods are `sendEInvoice`, `syncEInvoices` and `receiveEInvoices`,
  behind the new `invoices.send` permission (tenant scope). They return errors as
  results. The SQL functions only record; the channel call stays in TypeScript.
- Access point adapters are not part of the library. An app or a package writes a
  channel over `fetch`.

## Consequences

Anyone using the old `sendEInvoice({ invoice, format, channel })` function, the
`body`/`filename`/`contentType` document or `name` and `externalRef` on a channel
moves to the new shape; the changeset has the table. A received document that
names an unknown sender is kept as `unmatched`, so nothing is lost and the app
decides what to do with it. Validation of the UBL stays outside the library.

ADR 0175 added a second log, `invoice_deliveries`, for the channel's reference.
It shipped in no release, so it is removed: `invoice_e_deliveries` keeps the
message id, and `recordEInvoiceDelivery` replaces `recordEInvoice`. When the
channel accepted a document but logging it failed, the `sendEInvoice` error
names the message id, so the app records it instead of sending again.
