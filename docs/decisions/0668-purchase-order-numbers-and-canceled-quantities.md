# 0668: Purchase orders take a number and give up quantity

- Status: accepted
- Date: 2026-11-10

## Context

A purchase order had no number of its own, and a supplier that couldn't deliver the whole order left
the buyer two choices: cancel the order, or keep a backorder that would never arrive and count as
incoming stock. The table already had optional `number` and `quantity_canceled` columns that no
function read or wrote (ADR 0640's follow-up list).

## Decision

`save_purchase_order` takes a trailing `number` argument (up to 50 characters). The unique index on
`(tenant_id, number)` makes a repeat fail with `INVENTORY_PURCHASE_ORDER_NUMBER_TAKEN`. An order
without a number gets one when it is placed: one more than the organization's highest all-digit
number, under a transaction advisory lock, so numbers don't skip and two placements can't take the
same one. The `numbering` block isn't used, because its sequences belong to the entities that carry a
sequence column; a purchase order keeps the plain rule and the buyer's own format in `number`. The
function replaces the old signature, and the argument exists only when the table has the column.

`cancel_purchase_order_quantity(purchase_order, lines)` raises `quantity_canceled` on lines of an
ordered or partly received order, by at most what each line still owes (`INVENTORY_OVER_CANCEL`),
and lowers the location's incoming stock by the same amount. Receiving checks a line against its
quantity minus what it canceled, the backorder count and `cancel_purchase_order` leave canceled
units out, and an order with nothing left owed becomes `received`, or `cancelled` when nothing was
received. It records `purchase_order.line_cancelled` and needs `inventory.purchase`.

## Consequences

Orders that never use either feature behave as before: the number stays null until placement, which
now fills it, and `quantity_canceled` stays zero. The migration replaces `save_purchase_order`, so a
caller that passes arguments by position must add the new one or use named arguments, which the
client does.
