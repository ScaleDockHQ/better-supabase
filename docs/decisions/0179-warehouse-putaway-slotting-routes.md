# 0179: Warehouse suggests putaway and slotting, orders pick routes and closes the picking task

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0169 left putaway, slotting and in-warehouse route optimization out, and a
completed pick list left its work item open for the app to move.

## Decision

Three small tables hold the inputs: `putaway_rules` (bin, optional variant,
priority, maximum quantity), `bin_slots` (walking rank, capacity per bin) and
`variant_sizes` (space per unit). `suggest_putaway` plans in four tiers: a rule
for the variant, a general rule, bins that already hold the variant, then free
bins by walking rank. It skips bins on hold or inactive, honours rule maximums
and capacity divided by size, and reports what fits nowhere as `unassigned`.
`suggest_receipt_putaway` groups a goods receipt by variant and exists only
when inventory has receipt tables. `suggest_slotting` ranks variants by pick
velocity over a window and pairs them with the closest bins that can hold the
stock. All three only suggest; stock moves through inventory.

Pick lines gain `route_position`. `set_pick_route` numbers the open lines of an
open list. The ordering itself runs in TypeScript: `optimizePickRoute` locates
each line through an app callback, calls the versioned `RouteOptimizer` port
(ADR 0158) with its nearest-neighbour fallback, and saves the order. Lines
without a point go last.

`complete_pick_list` sets the picker's work item to the tasks block's completed
state when tasks is installed.

## Consequences

- Warehouse stays free of coordinates; the app maps bins to points.
- Suggestions are advisory, so a stale rule never blocks a receipt.
- Apps that moved the task themselves find it already done.
- Adopted bin slot and size tables need unique indexes on bin and variant.
