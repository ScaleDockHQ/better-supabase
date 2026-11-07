# 0267: Inventory gets a reorder quantity, a serial pick and composite keys

- Status: accepted
- Date: 2026-11-07
- Amends: 0127

## Context

Part 5 of the declarative base layer plan lists the inventory gaps that make an
app write SQL beside the block. An audit of the code found most of them shipped:
`release_allocation` and `transfer_allocation` with their client methods,
`incoming` on the levels (placing a purchase order adds it, receiving removes
it), `inventory_overview` as the stock page read, and the locale tax codes in
the tax block's seeds. Four remained.

## Decision

- `stock_levels.reorder_quantity` (null, or above zero) with
  `set_reorder_quantity(variant, location, quantity)` and `setReorderQuantity`.
  The plan says "reorder fields" without naming them; the simplest reading is
  the quantity to order next to the existing reorder point.
- `pick_serials(variant, location, quantity, lot)` returns the serial numbers to
  take, oldest first (ties by serial number), and changes nothing. A caller
  passes them in the `detail` of `adjust_stock`, which keeps the single place
  that moves stock. Fewer serials than asked fails with `INVENTORY_INSUFFICIENT`.
- `unique (id, tenant_id)` on locations, reservations, transfers and purchase
  orders, so an app table references them with a composite key that carries the
  tenant.

Both functions are security definer like their neighbours (`stock_detail`,
`set_reorder_point`): signed-in users have no grant on the stock tables. The
inventory baseline goes from 295 to 307 (the count includes the api wrappers of
each function).

## Not done

- The purchase order document: it needs a rendering contract that the documents
  block owns, and a purchase order already has its lines and totals through
  `save_purchase_order`. It stays an app file until the documents block takes a
  purchase order source.
- `api` reads beyond `inventory_overview`, `stock_detail`, `stock_valuation` and
  `list_allocations`: the plan names no read that is missing.

## Consequences

An app that added a reorder column, picked serials in SQL or declared the
composite keys itself can delete those files. A stored `reorder_quantity` is
read by an app job; the block emits no event for it.
