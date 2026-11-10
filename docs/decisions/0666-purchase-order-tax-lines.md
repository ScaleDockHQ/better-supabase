# 0666: Purchase orders keep tax lines

- Status: accepted
- Date: 2026-11-10

## Context

A purchase order stored a unit cost per line and nothing about tax. A buyer who receives a supplier's
bill needs the expected tax per code and rate to compare with it, and the books need the same split.
The order lines already had an optional `tax_code` column that no function wrote.

## Decision

`purchase_order_lines` gets an optional `tax_rate_bps` column (0 to 100000), and a new optional table
`purchase_order_tax_lines` holds one row per tax code and rate: `tax_code`, `tax_rate_bps`, `net`,
`tax` and `gross`, in minor units of the order's currency.

`save_purchase_order` reads `taxRateBps` and `taxCode` per line and rebuilds the tax lines each time the
draft is saved, in the same statement as the line replacement. A line's net is its quantity times its
unit cost, rounded to a minor unit, and its tax is that quantity and cost at the line's rate, rounded
the same way. The rows add the lines up per code and rate, and a line without a rate adds none.
`purchase_order_tax_lines(purchase_order)` returns the currency and the rows, readable with
`inventory.read`, and the client reads them with `inventory.purchaseOrderTaxLines`.

## Consequences

Totals are stored per tax line, not on the order, so the order has no new total column and receiving
and cancelling leave the tax lines as they were saved. The rounding is per line, as for invoices and
quotes, so a bill that rounds per document can differ by a cent. The table is optional like the other
purchase order tables, and the read function exists only when the order keeps tax lines.
