---
"better-supabase": minor
---

Assets now carry a book value. `updateAsset` sets `acquisitionCost`, `acquiredOn`,
`usefulLifeMonths`, `residualValue`, `depreciationMethod` (`none`, `straight_line` or
`declining_balance`) and `depreciationRateBps`. `runDepreciation({ organizationId?, until? })`
books each month once into the new `asset_depreciations` table (service role only, so run it from
a cron route), `depreciations(assetId)` lists the months, and `dispose(assetId, { on, proceeds? })`
retires an asset and records its disposal. With `accounting` installed, depreciation posts through
the `depreciation_expense` and `accumulated_depreciation` roles and a disposal posts the gain or
loss through the new `disposal_gain` and `disposal_loss` roles, which fall back to the suspense
account until an organization maps them. Depreciating and disposing record `asset.depreciated` and
`asset.disposed`.

Projects get costing. `saveProject` takes a `budget` (`Money`) and `budgetHours`, and with
`accounting` installed each project becomes a value of the `project` dimension on its next save.
Billable-time rates take a cost: `setRate` accepts `cost`, so the SQL `set_time_rate` function has
a new `cost_amount` argument and its old signature is dropped. `projectCosts(projectId)` sums the
time logged on the project's work items at cost and as billed, the accounting lines on the
project dimension, the margin and the share of the budget used. Apply the new migration with
`better-supabase upgrade`.
