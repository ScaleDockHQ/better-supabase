# 0664: Staff orders take draft and on-hold states

- Status: accepted
- Date: 2026-11-10

## Context

The orders block made two kinds of order. A cart checkout starts at `pending_payment`, and an order
staff enter from lines or from an accepted quote starts `confirmed` and allocates its stock at once.
Staff had no way to prepare an order before it claimed stock, and no way to pause one while a person
sorted out a credit check or a customer question. CentraKit kept both in its own status column and
worked around the block's transitions.

## Decision

Two statuses join the order lifecycle: `draft` and `on_hold`.

`order_from_lines` and `order_from_quote` take `draft` in their attrs. A draft order has its lines and
totals, a number and its origin, but it allocates no stock and records `order.drafted` instead of
`order.placed`. `confirm_draft_order(order_id, location)` moves it to `confirmed`, allocates its stock
and records `order.placed`. `cancel_order` also cancels a draft.

`hold_order(order_id, reason)` moves an order that waits for payment, or a confirmed one, to
`on_hold`. The order keeps its stock reservations and allocations, doesn't expire, and can't be
fulfilled, because every fulfillment check already asks for a paid or confirmed order.
`release_order_hold(order_id)` returns it to the status it was held from. The table gets three
optional columns, `held_at`, `held_from` and `hold_reason`; without `held_from` an app's own orders
table gets no hold functions, in line with ADR 0580. A paid order can't be held, so a cancel from
`on_hold` never needs a refund. Both functions need `orders.manage` and record `order.hold_placed` and
`order.hold_released`.

The built-in edges gain `draft` to `confirmed` or `cancelled`, `pending_payment` and `confirmed` to
`on_hold`, and `on_hold` back to `pending_payment`, `confirmed` or `cancelled`. A state machine on the
status column still replaces them.

## Consequences

A payment recorded while an order is on hold is stored on the order but doesn't move it to paid, since
`record_payment` only pays orders waiting for payment or confirmed. The app releases the hold and
records the payment again, which is idempotent on the provider reference. The order board lists the
two statuses in lifecycle order. Existing orders and the cart checkout are unchanged, and the
migration adds nullable columns and replaces functions.
