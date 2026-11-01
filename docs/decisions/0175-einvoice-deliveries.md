# 0175: Sent e-invoices keep the channel's reference in `invoice_deliveries`

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0159 made e-invoice formats and channels versioned ports. `sendEInvoice`
returned the channel's `externalRef` and recorded nothing, so every app had to
store it to ask `channel.status` later, and a crash between the send and the
save lost the reference.

## Decision

The invoices module gains an optional table `invoice_deliveries` (`optionalTable`,
so an app can map its own): the invoice, the channel key, the format key, the
`external_ref`, an optional filename, who sent it and when. A unique index on
the invoice, the channel and the reference makes a retried record a no-op.

Two functions read and write it. `record_invoice_delivery(invoice, channel,
format, external_ref, filename)` needs the `invoices.issue` permission, refuses a
draft or void invoice (`EINVOICE_NOT_ISSUED`) and returns the first row for a
reference it already holds. `list_invoice_deliveries(invoice)` needs read access
and lists newest first.

`sendEInvoice` takes the invoices client as `invoices` and calls
`recordEInvoice` after the channel accepted the document. When keeping the
reference fails, the error message names the `externalRef`, so the app records
it with `recordEInvoice` instead of sending the document again. The delivery
result gains `deliveryId`. The invoices client also exposes `recordEInvoice` and
`eInvoiceDeliveries`.

## Alternatives considered

- A column `external_ref` on the invoice. An invoice can go out through more
  than one channel, and a resend returns a new reference, so one column loses
  history.
- Keep the call pure and document the manual save. That is the gap this
  decision closes.

## Consequences

- `sendEInvoice` has a required `invoices` option (breaking for 0.x callers, who
  pass `invoices` and drop their own save).
- Apps run `upgrade` and generate a migration for the new table and two functions.
- Amends ADR 0159.
