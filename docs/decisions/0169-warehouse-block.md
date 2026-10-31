# 0169: Warehouse picks from allocations and schedules cycle counts

- Status: accepted
- Date: 2026-10-31

## Context

`inventory` allocates stock to documents (`stock_allocations`), keeps bins, lots
and serial numbers, and has stock counts with a variance per line. Nothing turns
an allocation into work for a picker, groups that work into waves, or opens
counts on a schedule and keeps a large variance from posting unseen.

## Decision

`warehouse` is a block (`better-supabase/blocks/warehouse`) with four tables:
`pick_waves`, `pick_lists`, `pick_lines` and `count_plans`. Every table is
adoptable (ADR 0098). It requires memberships, permissions and inventory, and
integrates with `tasks`, `relations`, outbox and audit.

- A pick line points at one allocation. `create_pick_list` makes a line per
  open allocation of a document at a location that holds stock and is on no
  open line, starting with the bin and lot that hold the most of the variant. A
  partial unique index keeps an allocation on one open line.
- Picking records what was found (`record_pick`) and never moves stock. The
  shipment takes it through `fulfill_allocation`, so a pick cannot double a
  movement. `complete_pick_list` turns lines with less picked than asked for
  into `short`; the wave completes with its last open list.
- With `tasks` installed a pick list gets a work item, linked with a
  `created_from` relation. A list in a wave gets it at `release_pick_wave`, a
  standalone list at creation. The block does not move the task: the app owns
  its states.
- A count plan stores an interval, optional variants and a variance limit
  (5 percent by default). `run_due_count_plans` opens counts through
  `open_stock_count` and is meant for a daily job. `post_cycle_count` computes
  each counted line's variance as a percent of the expected quantity (at least
  one) and posts through `post_stock_count` only when the largest is within the
  limit or `approve` is true. Counts, lines and postings stay inventory's.
- Permissions are `warehouse.read`, `warehouse.pick` and `warehouse.manage`.
  Owners and admins hold all of them, and members hold `warehouse.pick`. A
  reader without `warehouse.read` reads only the lists assigned to them.
- Events are `pick_wave.created|released|completed`, `pick_list.created|picked`
  and `count_plan.created|executed`. The hooks are `before_pick_list_create`
  and `after_pick_list_create`.

## Consequences

- A warehouse needs no second stock model: allocations, bins, lots, serials and
  counts stay in inventory, and the block only adds work and a review gate.
- Opening and posting a count needs `inventory.manage` as well as
  `warehouse.manage`, because inventory guards its own functions.
- Putaway, slotting and in-warehouse route optimization are not covered.
- The block needs the inventory block's count tables; the build fails without
  them.
