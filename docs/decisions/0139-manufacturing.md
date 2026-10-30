# 0139: BOM versions, production orders over `move_stock`, and lot genealogy in `stock_lot_links`

- Status: accepted
- Date: 2026-10-30

## Context

Food, cosmetics, furniture and small electronics makers run on the
`inventory` block (ADR 0127) and need to make products from other products:
what one unit takes (a bill of materials), where and how long it's made (a
routing on work centers), production orders that take components out of
stock and put the output in at its real cost, and the trace a recall needs:
which finished lots a bad lot of raw material went into, where they are now
and who got them. Planning needs the shortages of every level netted
against stock, incoming orders and open production.

## Decision

- **One block over inventory.** `manufacturing` requires `catalog`,
  `inventory` and `numbering`, and owns `boms`, `bom_components`,
  `bom_operations`, `work_centers`, `production_orders`,
  `production_order_operations`, `production_consumptions` and
  `stock_lot_links`. It integrates `assets` (the machine of a work center),
  `drive` (work instructions), `inspections` (an inspection per operation)
  and `accounting` (labor).
- **Versioned bills of materials.** Each save of a variant's bill of
  materials is a new `draft` version; `activate_bom` makes one `active` and
  archives the one before. An order pins the version it was created with, so
  changing a recipe never changes an order in flight. Activation walks the
  active versions of every component and refuses a cycle (`BOM_CYCLE`);
  explosions and where-used stop at 20 levels.
- **Every stock change through `move_stock`.** A release allocates the
  components through the inventory allocations of document type
  `production_order`; consumption takes from them with the new reason
  `consumption` (outbound, so it skips hold bins and expired lots) through
  `take_allocation`, the function `fulfill_allocation` now calls with
  `sale`. The output arrives with the new reason `production` (inbound, so
  a lot-tracked variant names its lot) at the material value consumed plus
  labor. Lots, serials, bins and average cost behave as for any other
  movement, and no table outside inventory holds stock.
- **Labor at the work center rate.** Each operation's minutes at its work
  center's cost rate per hour. With `accounting`, a completed order with
  labor books a `production_order` source: work in progress against
  expense. The consumption and the output book through the inventory
  `stock_movement` source against the new `work_in_progress` role, so work
  in progress nets to zero once the order is done.
- **Genealogy as links.** On completion every output lot gets a row in
  `stock_lot_links` per lot the order consumed, keyed by the parent lot,
  child lot and order. `lot_genealogy` walks it up or down with a recursive
  query; `lot_recall` adds the stock still on hand, the documents the lots
  left stock for and the orders that consumed them.
- **Requirements in SQL.** `material_requirements` nets the reorder point and
  open demand within a horizon against available, incoming and planned
  quantities, level by level through active versions, and suggests
  `produce` or `purchase`. `create_from_requirements` turns chosen
  suggestions into draft production orders and the inventory block's draft
  purchase orders.
- **Permissions.** `manufacturing.read`, `write`, `produce` and `manage`.
  Members hold `read` and `produce`, so the shop floor runs operations and
  completes orders while planners draft and release them.

## Alternatives considered

- **Stock in the manufacturing tables.** Keeping work in progress and
  output in the block's own tables would give two stock ledgers and break
  average cost, lot expiry and bin holds for made products.
- **Genealogy from the ledger.** The ledger lines carry the lot and the
  order reference, so genealogy could be derived from them. A recall then
  joins every movement of a tenant per level; the link table answers it
  from an index.
- **Editable bills of materials.** Editing in place is simpler, but a
  released order would then make something other than what it allocated,
  and costing history would no longer explain past orders.

## Consequences

Apps get manufacturing with one `add manufacturing` on top of inventory.
Capacity planning (finite scheduling of work centers), by-products and
co-products, subcontracting and a purchasing block with requisitions and
approvals aren't part of it; when purchasing ships,
`create_from_requirements` creates requisitions through it instead of draft
purchase orders. Revisit when an app needs routings that branch or orders
that produce several variants.
