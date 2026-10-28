---
"better-supabase": minor
---

Blocks run over more of an app's own tables.

- `upgrade`, `sync` and doctor render adopted tables with the authorization provider, so calendar `accessFunctions` in the `{ rows, key }` form and drive `roleFunctions` in the `{ rows, roles }` form no longer fail with "needs an authorization provider with functions.rowsWith".
- Drive: a node under a held folder counts as held, so it can't be trashed, deleted or pruned by a sync. With `roleFunctions.node`, a new top-level node no longer gets an owner grant for its creator.
- Time tracking: a submitted or approved week refuses only changes to logged time (start, end or duration, subject, owner and rate). The billable flag, the note and app columns stay writable, and `options.lockedColumns` lists other columns.
- Invoices: `options.chargeExtraColumns` adds app columns to charges, set through `charge(id, { fields })`. `options.lineRates: "percent"` keeps line discount and tax rates as percentages in the app's line table (invoices, quotes and deals).
- Catalog: `save_product` writes the product's own `price`, `currency` and `trackInventory` without a prices table. `options.variantExtraColumns` and `options.categoryExtraColumns` let `saveVariant` and `saveCategory` write app columns from `fields`.
- Leave: `columns.types.key` and `columns.requests.partial` can map to `null`.
