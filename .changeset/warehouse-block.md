---
"better-supabase": minor
---

New `warehouse` block (`better-supabase/blocks/warehouse`): pick waves and pick lists made from `inventory` allocations, picking work items, and cycle count plans.

- `createPickList` makes a line per open allocation of a document at a location, starting with the bin and lot that hold the most stock. `recordPick` confirms the bin, lot and serial numbers and the quantity found, and `completePickList` marks lines with less picked than asked for as `short`. Stock moves when the document ships, not when it is picked.
- `createPickWave`, `releasePickWave` and `cancelPickWave` group lists. With the `tasks` block each list gets a work item for the picker.
- `createCountPlan`, `runDueCountPlans` and `runCountPlan` open `inventory` stock counts on a schedule. `postCycleCount` posts a count through inventory and holds one with a line over the plan's variance limit (5 percent by default) until it is called with `approve: true`.
- The permission keys are `warehouse.read`, `warehouse.pick` and `warehouse.manage`.

Add `warehouse: {}` to `blocks`, run `better-supabase add warehouse` and generate a migration.
